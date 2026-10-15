const std = @import("std");
const linux = std.os.linux;
const common = @import("common");

const MyArrayList = common.MyArrayList;
const envOrDefault = common.envOrDefault;
const fileExists = common.fileExists;
const getErrno = common.getErrno;
const pathToZ = common.pathToZ;
const sysClose = common.sysClose;
const sysGetdents64 = common.sysGetdents64;
const sysOpen = common.sysOpen;
const writeStderr = common.writeStderr;

const DEFAULT_LOG_DIR = "/var/log/alpenglow";
const DEFAULT_MAX_LOGS: u32 = 7;

fn sysUnlink(path: []const u8) void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return;
    _ = linux.unlink(path_z);
}

fn sysRename(old_path: []const u8, new_path: []const u8) void {
    var old_buf: [4096]u8 = undefined;
    var new_buf: [4096]u8 = undefined;
    const old_z = pathToZ(old_path, &old_buf) orelse return;
    const new_z = pathToZ(new_path, &new_buf) orelse return;
    _ = linux.rename(old_z, new_z);
}

pub fn isRotatableLogName(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".log") and name.len > ".log".len;
}

pub fn rotateLogFile(allocator: std.mem.Allocator, log_path: []const u8, max_logs: u32) !void {
    if (max_logs == 0) return;

    const oldest = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ log_path, max_logs });
    defer allocator.free(oldest);
    sysUnlink(oldest);

    var i: u32 = max_logs;
    while (i > 1) : (i -= 1) {
        const prev = i - 1;
        const prev_path = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ log_path, prev });
        defer allocator.free(prev_path);
        const curr_path = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ log_path, i });
        defer allocator.free(curr_path);
        if (fileExists(prev_path)) {
            sysRename(prev_path, curr_path);
        }
    }

    const first_rot = try std.fmt.allocPrint(allocator, "{s}.1", .{log_path});
    defer allocator.free(first_rot);
    if (fileExists(log_path)) {
        sysRename(log_path, first_rot);
    }
}

pub fn rotateDirectory(allocator: std.mem.Allocator, log_dir: []const u8, max_logs: u32) !void {
    var path_buf: [4096]u8 = undefined;
    const dir_z = pathToZ(log_dir, &path_buf) orelse return error.NameTooLong;
    const dir_fd = sysOpen(dir_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer sysClose(dir_fd);

    var logs = MyArrayList([]const u8).init(allocator);
    defer {
        for (logs.items()) |item| allocator.free(item);
        logs.deinit();
    }

    var dents_buf: [4096]u8 align(8) = undefined;
    while (true) {
        const n = try sysGetdents64(dir_fd, &dents_buf);
        if (n == 0) break;
        var offset: usize = 0;
        while (offset < n) {
            const entry = @as(*linux.dirent64, @ptrCast(@alignCast(&dents_buf[offset])));
            const name_ptr: [*:0]u8 = @ptrCast(&entry.name);
            const name = std.mem.span(name_ptr);
            if (isRotatableLogName(name)) {
                if (entry.type == linux.DT.REG or entry.type == linux.DT.UNKNOWN) {
                    const full = try std.fs.path.join(allocator, &[_][]const u8{ log_dir, name });
                    try logs.append(full);
                }
            }
            offset += entry.reclen;
        }
    }

    for (logs.items()) |log_path| {
        try rotateLogFile(allocator, log_path, max_logs);
    }
}

pub fn run() !void {
    const allocator = std.heap.page_allocator;
    const log_dir = envOrDefault("ALPENGLOW_LOGROTATE_DIR", DEFAULT_LOG_DIR);
    const max_str = envOrDefault("ALPENGLOW_LOGROTATE_MAX", "7");
    const max_logs = std.fmt.parseInt(u32, max_str, 10) catch DEFAULT_MAX_LOGS;

    rotateDirectory(allocator, log_dir, max_logs) catch |err| {
        writeStderr("alpenglow-logrotate: ");
        writeStderr(@errorName(err));
        writeStderr("\n");
        std.process.exit(1);
    };
}

test "isRotatableLogName matches only valid .log files" {
    const testing = std.testing;
    try testing.expect(isRotatableLogName("system.log"));
    try testing.expect(isRotatableLogName("a.log"));
    try testing.expect(!isRotatableLogName(".log"));
    try testing.expect(!isRotatableLogName("system.log.1"));
    try testing.expect(!isRotatableLogName("readme.txt"));
}

test "rotateDirectory rotates logs up to max_logs" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .linux) return;

    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try std.fs.path.join(testing.allocator, &[_][]const u8{ ".zig-cache", "tmp", &tmp.sub_path });
    defer testing.allocator.free(dir_path);

    const log_file = try std.fs.path.join(testing.allocator, &[_][]const u8{ dir_path, "app.log" });
    defer testing.allocator.free(log_file);
    const rot1 = try std.fs.path.join(testing.allocator, &[_][]const u8{ dir_path, "app.log.1" });
    defer testing.allocator.free(rot1);
    const rot2 = try std.fs.path.join(testing.allocator, &[_][]const u8{ dir_path, "app.log.2" });
    defer testing.allocator.free(rot2);

    try common.writeFile(log_file, "gen2", true);
    try common.writeFile(rot1, "gen1", true);

    try rotateDirectory(testing.allocator, dir_path, 3);

    try testing.expect(!fileExists(log_file));
    try testing.expect(fileExists(rot1));
    try testing.expect(fileExists(rot2));
}
