const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

const ZRAM_CONTROL = "/sys/class/zram-control";
const ZRAM0 = "/sys/block/zram0";
const ZRAM0_DEV = "/dev/zram0";
const MEMINFO = "/proc/meminfo";

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

fn fileExists(path: []const u8) bool {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return false;
    const rc = linux.access(path_z, linux.F_OK);
    return getErrno(rc) == .SUCCESS;
}

fn readMemTotalKb() !u64 {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(MEMINFO, &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .CLOEXEC = true }, 0);
    defer sysClose(fd);
    var buf: [4096]u8 = undefined;
    const n = try sysRead(fd, &buf);
    const content = buf[0..n];
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "MemTotal:")) continue;
        const value = std.mem.trim(u8, line["MemTotal:".len..], " \t");
        var it = std.mem.splitScalar(u8, value, ' ');
        const num = it.next() orelse continue;
        return std.fmt.parseInt(u64, std.mem.trim(u8, num, " \t"), 10) catch continue;
    }
    return error.MemTotalNotFound;
}

fn writeZramDisksize(size_kb: u64) !void {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(ZRAM0 ++ "/disksize", &path_buf) orelse return error.NameTooLong;
    const value = try std.fmt.allocPrint(std.heap.page_allocator, "{d}K", .{size_kb});
    defer std.heap.page_allocator.free(value);
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, value);
}

fn hotAddZram() !void {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(ZRAM_CONTROL ++ "/hot_add", &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, "1");
}

fn writeStderr(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

fn spawnAndWait(argv: []const []const u8) !void {
    if (argv.len == 0 or argv.len > 16) return error.ChildProcessFailed;
    var buf: [16][256]u8 = undefined;
    var arg_ptrs: [17:null]?[*:0]u8 = undefined;
    for (argv, 0..) |arg, i| {
        if (arg.len >= 256) return error.ChildProcessFailed;
        @memcpy(buf[i][0..arg.len], arg);
        buf[i][arg.len] = 0;
        arg_ptrs[i] = buf[i][0..arg.len :0];
    }
    arg_ptrs[argv.len] = null;
    const env_array = &[_:null]?[*:0]const u8{null};
    const env: [*:null]const ?[*:0]const u8 = env_array;

    const pid = linux.fork();
    if (pid == 0) {
        _ = linux.execve(arg_ptrs[0].?, &arg_ptrs, env);
        std.process.exit(255);
    } else if (getErrno(pid) != .SUCCESS) {
        return error.ChildProcessFailed;
    } else {
        var status: u32 = undefined;
        while (true) {
            const rc = linux.waitpid(@intCast(pid), &status, 0);
            if (getErrno(rc) != .SUCCESS) {
                if (getErrno(rc) == .INTR) continue;
                return error.ChildProcessFailed;
            }
            break;
        }
        const code = linux.W.EXITSTATUS(status);
        if (code != 0 and code != 255) return error.ChildProcessFailed;
    }
}

pub fn main() !void {
    if (!fileExists(ZRAM_CONTROL)) {
        writeStderr("zramctl: zram-control not available\n");
        std.process.exit(1);
    }

    if (!fileExists(ZRAM0)) {
        hotAddZram() catch |err| {
            writeStderr("zramctl: hot_add failed: ");
            writeStderr(@errorName(err));
            writeStderr("\n");
            std.process.exit(1);
        };
    }

    const mem_kb = readMemTotalKb() catch |err| {
        writeStderr("zramctl: cannot read MemTotal: ");
        writeStderr(@errorName(err));
        writeStderr("\n");
        std.process.exit(1);
    };
    const size_kb = mem_kb / 2;
    if (size_kb == 0) {
        writeStderr("zramctl: zero memory, aborting\n");
        std.process.exit(1);
    }

    writeZramDisksize(size_kb) catch |err| {
        writeStderr("zramctl: cannot set disksize: ");
        writeStderr(@errorName(err));
        writeStderr("\n");
        std.process.exit(1);
    };

    if (fileExists("/usr/sbin/mkswap") and fileExists("/usr/sbin/swapon")) {
        spawnAndWait(&.{ "/usr/sbin/mkswap", ZRAM0_DEV }) catch {};
        spawnAndWait(&.{ "/usr/sbin/swapon", ZRAM0_DEV }) catch {};
    }
}
