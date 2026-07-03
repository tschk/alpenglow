const std = @import("std");
const linux = std.os.linux;
const common = @import("common");

const SyscallError = common.SyscallError;
const getErrno = common.getErrno;
const checkSyscall = common.checkSyscall;
const pathToZ = common.pathToZ;
const sysOpen = common.sysOpen;
const sysRead = common.sysRead;
const sysWrite = common.sysWrite;
const sysClose = common.sysClose;
const sysMkdir = common.sysMkdir;
const makeDir = common.makeDir;
const makePathRecursive = common.makePathRecursive;
const writeFile = common.writeFile;
const writeStderr = common.writeStderr;

const DEFAULT_PRESSURE_PATH = "/proc/pressure/memory";
const DEFAULT_STATE_JSON = "/run/alpenglow/pressurectl/state.json";

extern "c" var environ: [*:null]?[*:0]u8;

const Pressure = struct {
    avg10: ?f64 = null,
    avg60: ?f64 = null,
    avg300: ?f64 = null,
    total: ?u64 = null,
};

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
