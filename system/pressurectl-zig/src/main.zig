const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

const DEFAULT_PRESSURE_PATH = "/proc/pressure/memory";
const DEFAULT_STATE_JSON = "/run/alpenglow/pressurectl/state.json";

extern "c" var environ: [*:null]?[*:0]u8;

const Pressure = struct {
    avg10: ?f64 = null,
    avg60: ?f64 = null,
    avg300: ?f64 = null,
    total: ?u64 = null,
};

const SyscallError = error{
    FileNotFound,
    AccessDenied,
    PathAlreadyExists,
    NotDir,
    IsDir,
    InvalidArgument,
    OutOfMemory,
    FileTooBig,
    InputOutput,
    DeviceBusy,
    WouldBlock,
    Interrupted,
    NameTooLong,
    NotEmpty,
    Unexpected,
};

fn getErrno(rc: usize) linux.E {
    const signed: isize = @bitCast(rc);
    if (signed > -4096 and signed < 0) {
        return @enumFromInt(-signed);
    }
    return .SUCCESS;
}

fn checkSyscall(rc: usize) SyscallError!void {
    switch (getErrno(rc)) {
        .SUCCESS => return,
        .NOENT => return error.FileNotFound,
        .ACCES => return error.AccessDenied,
        .EXIST => return error.PathAlreadyExists,
        .NOTDIR => return error.NotDir,
        .ISDIR => return error.IsDir,
        .INVAL => return error.InvalidArgument,
        .NOMEM => return error.OutOfMemory,
        .FBIG => return error.FileTooBig,
        .IO => return error.InputOutput,
        .BUSY => return error.DeviceBusy,
        .AGAIN => return error.WouldBlock,
        .INTR => return error.Interrupted,
        .NAMETOOLONG => return error.NameTooLong,
        .NOTEMPTY => return error.NotEmpty,
        else => return error.Unexpected,
    }
}

fn getenv(key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (environ[i]) |entry| : (i += 1) {
        const e = std.mem.span(entry);
        if (std.mem.startsWith(u8, e, key) and e.len > key.len and e[key.len] == '=') {
            return e[key.len + 1 ..];
        }
    }
    return null;
}

fn envOrDefault(key: []const u8, default: []const u8) []const u8 {
    return getenv(key) orelse default;
}

fn pathToZ(path: []const u8, buf: []u8) ?[:0]const u8 {
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

fn sysOpen(path: [*:0]const u8, flags: linux.O, mode: linux.mode_t) SyscallError!i32 {
    const rc = linux.open(path, flags, mode);
    try checkSyscall(rc);
    return @intCast(rc);
}

fn sysRead(fd: i32, buf: []u8) SyscallError!usize {
    const rc = linux.read(fd, buf.ptr, buf.len);
    try checkSyscall(rc);
    return rc;
}

fn sysWrite(fd: i32, data: []const u8) SyscallError!void {
    var written: usize = 0;
    while (written < data.len) {
        const rc = linux.write(fd, data.ptr + written, data.len - written);
        try checkSyscall(rc);
        written += rc;
    }
}

fn sysClose(fd: i32) void {
    _ = linux.close(fd);
}

fn sysMkdir(path: [*:0]const u8, mode: linux.mode_t) SyscallError!void {
    const rc = linux.mkdir(path, mode);
    if (getErrno(rc) == .EXIST) return;
    try checkSyscall(rc);
}

fn makeDir(path: []const u8) SyscallError!void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    try sysMkdir(path_z, 0o755);
}

fn makePathRecursive(path: []const u8) !void {
    if (path.len == 0 or std.mem.eql(u8, path, "/")) return;
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') {
            makeDir(path[0..i]) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
    }
    makeDir(path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn readPressure(path: []const u8) !Pressure {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .CLOEXEC = true }, 0);
    defer sysClose(fd);
    var buf: [4096]u8 = undefined;
    const n = try sysRead(fd, &buf);
    const content = buf[0..n];
    var p = Pressure{};
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "some ")) continue;
        var it = std.mem.splitScalar(u8, line["some ".len..], ' ');
        while (it.next()) |part| {
            if (std.mem.startsWith(u8, part, "avg10=")) {
                p.avg10 = std.fmt.parseFloat(f64, part["avg10=".len..]) catch null;
            } else if (std.mem.startsWith(u8, part, "avg60=")) {
                p.avg60 = std.fmt.parseFloat(f64, part["avg60=".len..]) catch null;
            } else if (std.mem.startsWith(u8, part, "avg300=")) {
                p.avg300 = std.fmt.parseFloat(f64, part["avg300=".len..]) catch null;
            } else if (std.mem.startsWith(u8, part, "total=")) {
                p.total = std.fmt.parseInt(u64, part["total=".len..], 10) catch null;
            }
        }
    }
    return p;
}

fn renderJson(gpa: std.mem.Allocator, p: Pressure) ![]const u8 {
    return std.fmt.allocPrint(gpa, "{{\"memory_some_avg10\":{d:.4},\"memory_some_avg60\":{d:.4},\"memory_some_avg300\":{d:.4},\"memory_some_total\":{d}}}\n", .{
        p.avg10 orelse 0,
        p.avg60 orelse 0,
        p.avg300 orelse 0,
        p.total orelse 0,
    });
}

fn writeFile(path: []const u8, data: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, data);
}

fn update(gpa: std.mem.Allocator, pressure_path: []const u8, state_json: []const u8) !void {
    const p = readPressure(pressure_path) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    const json = try renderJson(gpa, p);
    defer gpa.free(json);
    if (std.fs.path.dirname(state_json)) |parent| {
        makePathRecursive(parent) catch {};
    }
    try writeFile(state_json, json);
}

fn sleepSeconds(seconds: u64) void {
    var req: linux.timespec = .{ .sec = @intCast(seconds), .nsec = 0 };
    var rem: linux.timespec = undefined;
    while (true) {
        const rc = linux.nanosleep(&req, &rem);
        if (getErrno(rc) == .SUCCESS) break;
        if (rem.sec <= 0 and rem.nsec <= 0) break;
        req = rem;
    }
}

fn writeStderr(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    const pressure_path = envOrDefault("ALPENGLOW_PRESSURECTL_PRESSURE_PATH", DEFAULT_PRESSURE_PATH);
    const state_json = envOrDefault("ALPENGLOW_PRESSURECTL_STATE_JSON", DEFAULT_STATE_JSON);

    while (true) {
        update(gpa, pressure_path, state_json) catch |err| {
            writeStderr("pressurectl: ");
            writeStderr(@errorName(err));
            writeStderr("\n");
        };
        sleepSeconds(60);
    }
}
