const std = @import("std");

fn syserr2errno(ret: u64) std.os.linux.E {
    const signed: i64 = @bitCast(ret);
    if (signed >= 0) return .SUCCESS;
    return @enumFromInt(-signed);
}

fn mount(src: [*:0]const u8, target: [*:0]const u8, fstype: [*:0]const u8, flags: u64, data: ?*anyopaque) !void {
    const ret = std.os.linux.syscall5(
        .mount,
        @intFromPtr(src),
        @intFromPtr(target),
        @intFromPtr(fstype),
        flags,
        @intFromPtr(data),
    );
    if (syserr2errno(ret) != .SUCCESS) {
        return error.MountFailed;
    }
}

fn mkdir(path: [*:0]const u8, mode: u32) void {
    _ = std.os.linux.syscall3(.mkdirat, @as(u64, @bitCast(@as(i64, -100))), @intFromPtr(path), mode);
}

fn write_console(msg: []const u8) void {
    const fd = std.os.linux.syscall3(.openat, @as(u64, @bitCast(@as(i64, -100))), @intFromPtr("/dev/console"), 0x101);
    if (fd >= 0) {
        _ = std.os.linux.syscall3(.write, @as(usize, @intCast(fd)), @intFromPtr(msg.ptr), msg.len);
        _ = std.os.linux.syscall1(.close, @as(usize, @intCast(fd)));
    }
}

fn exec_dinit() noreturn {
    const argv = [_:null]?[*:0]const u8{
        "/sbin/dinit",
        "-d",
        "/etc/dinit.d",
        "-s",
        "-t",
        "boot",
        null,
    };
    const envp = [_:null]?[*:0]const u8{null};
    _ = std.os.linux.syscall3(.execve, @intFromPtr(argv[0].?), @intFromPtr(&argv), @intFromPtr(&envp));
    // If exec fails, panic/hang.
    while (true) {}
}

pub fn main() void {
    @setRuntimeSafety(false);

    mkdir("/proc", 0o555);
    mount("proc", "/proc", "proc", 0, null) catch {};

    mkdir("/sys", 0o555);
    mount("sysfs", "/sys", "sysfs", 0, null) catch {};

    mkdir("/dev", 0o755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, null) catch {};

    mkdir("/run", 0o755);
    mount("tmpfs", "/run", "tmpfs", 0, null) catch {};

    mkdir("/dev/shm", 0o1777);
    mount("tmpfs", "/dev/shm", "tmpfs", 0, @ptrFromInt(@intFromPtr("mode=1777,size=256m"))) catch {};

    mkdir("/run/user", 0o755);
    mkdir("/run/user/0", 0o700);
    mkdir("/state", 0o755);

    write_console("\nAlpenglow boot\n\n");

    exec_dinit();
}
