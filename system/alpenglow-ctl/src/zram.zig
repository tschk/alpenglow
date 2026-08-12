const std = @import("std");
const linux = std.os.linux;
const common = @import("common");

const ZRAM_CONTROL = "/sys/class/zram-control";
const ZRAM0 = "/sys/block/zram0";
const ZRAM0_DEV = "/dev/zram0";
const MEMINFO = "/proc/meminfo";

const SyscallError = common.SyscallError;
const getErrno = common.getErrno;
const checkSyscall = common.checkSyscall;
const pathToZ = common.pathToZ;
const sysOpen = common.sysOpen;
const sysRead = common.sysRead;
const sysWrite = common.sysWrite;
const sysClose = common.sysClose;
const fileExists = common.fileExists;
const writeStderr = common.writeStderr;

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

fn runInternal(comptime Env: type, env: *Env) !void {
    if (!env.fileExists(ZRAM_CONTROL)) {
        env.writeStderr("zramctl: zram-control not available\n");
        return env.exit(1);
    }

    if (!env.fileExists(ZRAM0)) {
        env.hotAddZram() catch |err| {
            env.writeStderr("zramctl: hot_add failed: ");
            env.writeStderr(@errorName(err));
            env.writeStderr("\n");
            return env.exit(1);
        };
    }

    const mem_kb = env.readMemTotalKb() catch |err| {
        env.writeStderr("zramctl: cannot read MemTotal: ");
        env.writeStderr(@errorName(err));
        env.writeStderr("\n");
        return env.exit(1);
    };
    if (mem_kb == 0) {
        env.writeStderr("zramctl: zero memory, aborting\n");
        return env.exit(1);
    }
    const size_kb = mem_kb / 2;

    env.writeZramDisksize(size_kb) catch |err| {
        env.writeStderr("zramctl: cannot set disksize: ");
        env.writeStderr(@errorName(err));
        env.writeStderr("\n");
        return env.exit(1);
    };

    if (env.fileExists("/usr/sbin/mkswap") and env.fileExists("/usr/sbin/swapon")) {
        env.spawnAndWait(&.{ "/usr/sbin/mkswap", ZRAM0_DEV }) catch |err| {
            env.writeStderr("zramctl: mkswap failed: ");
            env.writeStderr(@errorName(err));
            env.writeStderr("\n");
        };
        env.spawnAndWait(&.{ "/usr/sbin/swapon", ZRAM0_DEV }) catch |err| {
            env.writeStderr("zramctl: swapon failed: ");
            env.writeStderr(@errorName(err));
            env.writeStderr("\n");
        };
    }
}

const ProdEnv = struct {
    fn fileExists(_: *ProdEnv, path: []const u8) bool { return common.fileExists(path); }
    fn hotAddZram(_: *ProdEnv) !void { return _hotAddZram(); }
    fn readMemTotalKb(_: *ProdEnv) !u64 { return _readMemTotalKb(); }
    fn writeZramDisksize(_: *ProdEnv, size_kb: u64) !void { return _writeZramDisksize(size_kb); }
    fn spawnAndWait(_: *ProdEnv, argv: []const []const u8) !void { return _spawnAndWait(argv); }
    fn writeStderr(_: *ProdEnv, msg: []const u8) void { common.writeStderr(msg); }
    fn exit(_: *ProdEnv, code: u8) !void { std.process.exit(code); }
};

pub fn run() !void {
    var env = ProdEnv{};
    try runInternal(ProdEnv, &env);
}

// Map the original global functions to ones without conflict
const _hotAddZram = hotAddZram;
const _readMemTotalKb = readMemTotalKb;
const _writeZramDisksize = writeZramDisksize;
const _spawnAndWait = spawnAndWait;

const TestEnv = struct {
    zram_control_exists: bool = true,
    zram0_exists: bool = true,
    mkswap_exists: bool = true,
    swapon_exists: bool = true,

    hot_add_error: ?anyerror = null,
    mem_total_kb: u64 = 1024 * 1024,
    mem_total_error: ?anyerror = null,
    disksize_error: ?anyerror = null,
    mkswap_error: ?anyerror = null,
    swapon_error: ?anyerror = null,

    exit_code: ?u8 = null,
    stderr: common.MyArrayList(u8),
    commands_run: common.MyArrayList([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) TestEnv {
        return .{
            .stderr = common.MyArrayList(u8).init(allocator),
            .commands_run = common.MyArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestEnv) void {
        self.stderr.deinit();
        for (self.commands_run.items()) |cmd| {
            self.allocator.free(cmd);
        }
        self.commands_run.deinit();
    }

    fn fileExists(self: *TestEnv, path: []const u8) bool {
        if (std.mem.eql(u8, path, ZRAM_CONTROL)) return self.zram_control_exists;
        if (std.mem.eql(u8, path, ZRAM0)) return self.zram0_exists;
        if (std.mem.eql(u8, path, "/usr/sbin/mkswap")) return self.mkswap_exists;
        if (std.mem.eql(u8, path, "/usr/sbin/swapon")) return self.swapon_exists;
        return false;
    }

    fn writeStderr(self: *TestEnv, msg: []const u8) void {
        self.stderr.appendSlice(msg) catch {};
    }

    fn exit(self: *TestEnv, code: u8) !void {
        self.exit_code = code;
        return error.Exit;
    }

    fn hotAddZram(self: *TestEnv) !void {
        if (self.hot_add_error) |err| return err;
        self.zram0_exists = true;
    }

    fn readMemTotalKb(self: *TestEnv) !u64 {
        if (self.mem_total_error) |err| return err;
        return self.mem_total_kb;
    }

    fn writeZramDisksize(self: *TestEnv, size_kb: u64) !void {
        if (self.disksize_error) |err| return err;
        const cmd = std.fmt.allocPrint(self.allocator, "disksize {d}", .{size_kb}) catch return;
        self.commands_run.append(cmd) catch {};
    }

    fn spawnAndWait(self: *TestEnv, argv: []const []const u8) !void {
        if (argv.len > 0 and std.mem.eql(u8, argv[0], "/usr/sbin/mkswap")) {
            if (self.mkswap_error) |err| return err;
        }
        if (argv.len > 0 and std.mem.eql(u8, argv[0], "/usr/sbin/swapon")) {
            if (self.swapon_error) |err| return err;
        }
        var full_cmd = common.MyArrayList(u8).init(self.allocator);
        defer full_cmd.deinit();
        for (argv, 0..) |arg, i| {
            full_cmd.appendSlice(arg) catch {};
            if (i < argv.len - 1) full_cmd.appendSlice(" ") catch {};
        }
        self.commands_run.append(full_cmd.toOwnedSlice() catch return) catch {};
    }
};

test "runInternal happy path" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();

    try runInternal(TestEnv, &env);

    try std.testing.expectEqual(@as(?u8, null), env.exit_code);
    try std.testing.expectEqualStrings("", env.stderr.items());
    try std.testing.expectEqual(@as(usize, 3), env.commands_run.items().len);
    try std.testing.expectEqualStrings("disksize 524288", env.commands_run.items()[0]);
    try std.testing.expectEqualStrings("/usr/sbin/mkswap /dev/zram0", env.commands_run.items()[1]);
    try std.testing.expectEqualStrings("/usr/sbin/swapon /dev/zram0", env.commands_run.items()[2]);
}

test "runInternal zram-control not available" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.zram_control_exists = false;

    try std.testing.expectError(error.Exit, runInternal(TestEnv, &env));
    try std.testing.expectEqual(@as(?u8, 1), env.exit_code);
    try std.testing.expectEqualStrings("zramctl: zram-control not available\n", env.stderr.items());
}

test "runInternal hot_add fails" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.zram0_exists = false;
    env.hot_add_error = error.SystemResources;

    try std.testing.expectError(error.Exit, runInternal(TestEnv, &env));
    try std.testing.expectEqual(@as(?u8, 1), env.exit_code);
    try std.testing.expectEqualStrings("zramctl: hot_add failed: SystemResources\n", env.stderr.items());
}

test "runInternal hot_add succeeds if zram0 missing" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.zram0_exists = false;

    try runInternal(TestEnv, &env);
    try std.testing.expectEqual(@as(?u8, null), env.exit_code);
    try std.testing.expect(env.zram0_exists);
}

test "runInternal mem_total fails" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.mem_total_error = error.FileNotFound;

    try std.testing.expectError(error.Exit, runInternal(TestEnv, &env));
    try std.testing.expectEqual(@as(?u8, 1), env.exit_code);
    try std.testing.expectEqualStrings("zramctl: cannot read MemTotal: FileNotFound\n", env.stderr.items());
}

test "runInternal mem_total zero" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.mem_total_kb = 0;

    try std.testing.expectError(error.Exit, runInternal(TestEnv, &env));
    try std.testing.expectEqual(@as(?u8, 1), env.exit_code);
    try std.testing.expectEqualStrings("zramctl: zero memory, aborting\n", env.stderr.items());
}

test "runInternal disksize fails" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.disksize_error = error.AccessDenied;

    try std.testing.expectError(error.Exit, runInternal(TestEnv, &env));
    try std.testing.expectEqual(@as(?u8, 1), env.exit_code);
    try std.testing.expectEqualStrings("zramctl: cannot set disksize: AccessDenied\n", env.stderr.items());
}

test "runInternal skip mkswap/swapon if missing" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.mkswap_exists = false;

    try runInternal(TestEnv, &env);
    try std.testing.expectEqual(@as(?u8, null), env.exit_code);
    // Only disksize is run
    try std.testing.expectEqual(@as(usize, 1), env.commands_run.items().len);
    try std.testing.expectEqualStrings("disksize 524288", env.commands_run.items()[0]);
}

test "runInternal mkswap fails" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.mkswap_error = error.ChildProcessFailed;

    try runInternal(TestEnv, &env);
    try std.testing.expectEqual(@as(?u8, null), env.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, env.stderr.items(), "zramctl: mkswap failed: ChildProcessFailed\n") != null);

    // swapon still runs
    try std.testing.expectEqual(@as(usize, 2), env.commands_run.items().len);
    try std.testing.expectEqualStrings("disksize 524288", env.commands_run.items()[0]);
    try std.testing.expectEqualStrings("/usr/sbin/swapon /dev/zram0", env.commands_run.items()[1]);
}

test "runInternal swapon fails" {
    var env = TestEnv.init(std.testing.allocator);
    defer env.deinit();
    env.swapon_error = error.ChildProcessFailed;

    try runInternal(TestEnv, &env);
    try std.testing.expectEqual(@as(?u8, null), env.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, env.stderr.items(), "zramctl: swapon failed: ChildProcessFailed\n") != null);

    // mkswap still ran
    try std.testing.expectEqual(@as(usize, 2), env.commands_run.items().len);
    try std.testing.expectEqualStrings("disksize 524288", env.commands_run.items()[0]);
    try std.testing.expectEqualStrings("/usr/sbin/mkswap /dev/zram0", env.commands_run.items()[1]);
}
