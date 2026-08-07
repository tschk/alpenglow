const std = @import("std");

var SHM_OPTS: [64:0]u8 = undefined;

fn shm_mount_opts() [*:0]const u8 {
    const AT_FDCWD: i64 = -100;
    const O_RDONLY: u32 = 0;
    const fd = std.os.linux.syscall3(.openat, @as(u64, @bitCast(AT_FDCWD)), @intFromPtr("/proc/meminfo"), O_RDONLY);
    if (syserr2errno(fd) != .SUCCESS) return "mode=1777,size=256m";
    var buf: [1024]u8 = undefined;
    const n = std.os.linux.syscall3(.read, @as(usize, @intCast(fd)), @intFromPtr(&buf), buf.len);
    _ = std.os.linux.syscall1(.close, @as(usize, @intCast(fd)));
    if (syserr2errno(n) != .SUCCESS) return "mode=1777,size=256m";
    var i: usize = 0;
    var total: u64 = 0;
    const prefix = "MemTotal:";
    while (i + prefix.len <= n) : (i += 1) {
        if (std.mem.eql(u8, buf[i .. i + prefix.len], prefix)) {
            i += prefix.len;
            while (i < n and (buf[i] == ' ' or buf[i] == '\t')) i += 1;
            while (i < n and buf[i] >= '0' and buf[i] <= '9') {
                total = total * 10 + (buf[i] - '0');
                i += 1;
            }
            break;
        }
    }
    if (total == 0) return "mode=1777,size=256m";
    _ = std.fmt.bufPrintZ(&SHM_OPTS, "mode=1777,size={}k", .{total / 2}) catch return "mode=1777,size=256m";
    return &SHM_OPTS;
}

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
    mount("tmpfs", "/dev/shm", "tmpfs", 0, @ptrFromInt(@intFromPtr(shm_mount_opts()))) catch {};

    mkdir("/run/user", 0o755);
    mkdir("/run/user/0", 0o700);
    mkdir("/state", 0o755);

    write_console("\nAlpenglow boot\n\n");

    exec_dinit();
}
