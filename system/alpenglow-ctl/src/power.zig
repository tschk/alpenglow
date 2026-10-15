const std = @import("std");
const linux = std.os.linux;
const common = @import("common");

const MyArrayList = common.MyArrayList;
const envOrDefault = common.envOrDefault;
const fileExists = common.fileExists;
const getErrno = common.getErrno;
const pathToZ = common.pathToZ;
const readFileLimited = common.readFileLimited;
const sysClose = common.sysClose;
const sysGetdents64 = common.sysGetdents64;
const sysOpen = common.sysOpen;
const sysWrite = common.sysWrite;
const writeStderr = common.writeStderr;

const DEFAULT_POWER_SUPPLY_DIR = "/sys/class/power_supply";
const DEFAULT_MEM_SLEEP_PATH = "/sys/power/state";

pub const PowerAction = enum {
    suspend_mem,
    hibernate,
    hybrid_sleep,
    status,
    help,
};

pub fn parsePowerAction(arg: []const u8) PowerAction {
    if (std.mem.eql(u8, arg, "suspend") or std.mem.eql(u8, arg, "s")) return .suspend_mem;
    if (std.mem.eql(u8, arg, "hibernate") or std.mem.eql(u8, arg, "h")) return .hibernate;
    if (std.mem.eql(u8, arg, "hybrid") or std.mem.eql(u8, arg, "hy") or std.mem.eql(u8, arg, "hybrid-sleep")) return .hybrid_sleep;
    if (std.mem.eql(u8, arg, "status")) return .status;
    return .help;
}

pub fn loginctlVerb(action: PowerAction) ?[]const u8 {
    return switch (action) {
        .suspend_mem => "suspend",
        .hibernate => "hibernate",
        .hybrid_sleep => "hybrid-sleep",
        else => null,
    };
}

pub fn sysPowerStateValue(action: PowerAction) ?[]const u8 {
    return switch (action) {
        .suspend_mem => "mem",
        .hibernate, .hybrid_sleep => "disk",
        else => null,
    };
}

fn writeStdout(msg: []const u8) void {
    _ = linux.write(1, msg.ptr, msg.len);
}

fn findLoginctl() ?[]const u8 {
    const candidates = [_][]const u8{
        "/usr/bin/loginctl",
        "/bin/loginctl",
        "/usr/local/bin/loginctl",
    };
    for (candidates) |path| {
        if (fileExists(path)) return path;
    }
    return null;
}

fn execLoginctl(verb: []const u8) !void {
    const bin = findLoginctl() orelse return error.LoginctlNotFound;
    var bin_buf: [256]u8 = undefined;
    var verb_buf: [64]u8 = undefined;
    const bin_z = pathToZ(bin, &bin_buf) orelse return error.NameTooLong;
    const verb_z = pathToZ(verb, &verb_buf) orelse return error.NameTooLong;

    var arg_ptrs = [_:null]?[*:0]const u8{ bin_z.ptr, verb_z.ptr, null };
    const env_array = &[_:null]?[*:0]const u8{null};

    const pid = linux.fork();
    if (pid == 0) {
        _ = linux.execve(bin_z.ptr, @ptrCast(&arg_ptrs), env_array);
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
        if (code != 0) return error.ChildProcessFailed;
    }
}

fn writeSysPowerState(state_path: []const u8, state_val: []const u8) !void {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(state_path, &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
    defer sysClose(fd);
    try sysWrite(fd, state_val);
}

pub fn collectPowerStatus(allocator: std.mem.Allocator, power_supply_dir: []const u8) ![]u8 {
    var out = MyArrayList(u8).init(allocator);
    errdefer out.deinit();

    var path_buf: [4096]u8 = undefined;
    const dir_z = pathToZ(power_supply_dir, &path_buf) orelse return error.NameTooLong;
    const base_fd = sysOpen(dir_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0) catch {
        try out.appendSlice("No battery\n");
        return try out.toOwnedSlice();
    };
    defer sysClose(base_fd);

    var names = MyArrayList([]const u8).init(allocator);
    defer {
        for (names.items()) |n| allocator.free(n);
        names.deinit();
    }

    var dents_buf: [4096]u8 align(8) = undefined;
    while (true) {
        const n = try sysGetdents64(base_fd, &dents_buf);
        if (n == 0) break;
        var offset: usize = 0;
        while (offset < n) {
            const entry = @as(*linux.dirent64, @ptrCast(@alignCast(&dents_buf[offset])));
            const name_ptr: [*:0]u8 = @ptrCast(&entry.name);
            const name = std.mem.span(name_ptr);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                if (entry.type == linux.DT.DIR or entry.type == linux.DT.LNK or entry.type == linux.DT.UNKNOWN) {
                    try names.append(try allocator.dupe(u8, name));
                }
            }
            offset += entry.reclen;
        }
    }

    std.mem.sort([]const u8, names.items(), {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var found_status = false;
    for (names.items()) |supply| {
        const status_path = try std.fs.path.join(allocator, &[_][]const u8{ power_supply_dir, supply, "status" });
        defer allocator.free(status_path);
        if (readFileLimited(allocator, status_path, 256)) |content| {
            defer allocator.free(content);
            const trimmed = std.mem.trim(u8, content, " \t\r\n");
            if (trimmed.len > 0) {
                found_status = true;
                try out.appendSlice(trimmed);
                try out.append('\n');
            }
        } else |_| {}
    }

    if (!found_status) {
        try out.appendSlice("No battery\n");
        return try out.toOwnedSlice();
    }

    for (names.items()) |supply| {
        const cap_path = try std.fs.path.join(allocator, &[_][]const u8{ power_supply_dir, supply, "capacity" });
        defer allocator.free(cap_path);
        if (readFileLimited(allocator, cap_path, 256)) |content| {
            defer allocator.free(content);
            const trimmed = std.mem.trim(u8, content, " \t\r\n");
            if (trimmed.len > 0) {
                try out.appendSlice(trimmed);
                try out.append('\n');
            }
        } else |_| {}
    }

    return try out.toOwnedSlice();
}

pub fn executeAction(allocator: std.mem.Allocator, action: PowerAction) !void {
    switch (action) {
        .suspend_mem, .hibernate, .hybrid_sleep => {
            const label = switch (action) {
                .suspend_mem => "→ Suspending...\n",
                .hibernate => "→ Hibernating...\n",
                .hybrid_sleep => "→ Hybrid sleep...\n",
                else => unreachable,
            };
            writeStdout(label);
            if (loginctlVerb(action)) |verb| {
                execLoginctl(verb) catch {
                    if (sysPowerStateValue(action)) |state_val| {
                        const state_path = envOrDefault("ALPENGLOW_POWER_STATE_PATH", DEFAULT_MEM_SLEEP_PATH);
                        try writeSysPowerState(state_path, state_val);
                    }
                };
            }
        },
        .status => {
            const supply_dir = envOrDefault("ALPENGLOW_POWER_SUPPLY_DIR", DEFAULT_POWER_SUPPLY_DIR);
            const out = try collectPowerStatus(allocator, supply_dir);
            defer allocator.free(out);
            writeStdout(out);
        },
        .help => {
            writeStderr("Usage: alpenglow-powerctl {suspend|hibernate|hybrid|status}\n");
        },
    }
}

pub fn runWithArgs(args: []const []const u8) !void {
    const allocator = std.heap.page_allocator;
    const action = if (args.len > 0) parsePowerAction(args[0]) else .status;
    try executeAction(allocator, action);
}

test "parsePowerAction maps aliases and defaults" {
    const testing = std.testing;
    try testing.expectEqual(PowerAction.suspend_mem, parsePowerAction("suspend"));
    try testing.expectEqual(PowerAction.suspend_mem, parsePowerAction("s"));
    try testing.expectEqual(PowerAction.hibernate, parsePowerAction("hibernate"));
    try testing.expectEqual(PowerAction.hibernate, parsePowerAction("h"));
    try testing.expectEqual(PowerAction.hybrid_sleep, parsePowerAction("hybrid"));
    try testing.expectEqual(PowerAction.hybrid_sleep, parsePowerAction("hy"));
    try testing.expectEqual(PowerAction.hybrid_sleep, parsePowerAction("hybrid-sleep"));
    try testing.expectEqual(PowerAction.status, parsePowerAction("status"));
    try testing.expectEqual(PowerAction.help, parsePowerAction("unknown"));
    try testing.expectEqual(PowerAction.help, parsePowerAction(""));
}

test "loginctlVerb and sysPowerStateValue" {
    const testing = std.testing;
    try testing.expectEqualStrings("suspend", loginctlVerb(.suspend_mem).?);
    try testing.expectEqualStrings("hibernate", loginctlVerb(.hibernate).?);
    try testing.expectEqualStrings("hybrid-sleep", loginctlVerb(.hybrid_sleep).?);
    try testing.expectEqual(@as(?[]const u8, null), loginctlVerb(.status));

    try testing.expectEqualStrings("mem", sysPowerStateValue(.suspend_mem).?);
    try testing.expectEqualStrings("disk", sysPowerStateValue(.hibernate).?);
    try testing.expectEqualStrings("disk", sysPowerStateValue(.hybrid_sleep).?);
    try testing.expectEqual(@as(?[]const u8, null), sysPowerStateValue(.help));
}
