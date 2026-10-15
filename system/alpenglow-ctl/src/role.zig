const std = @import("std");
const common = @import("common");

const envOrDefault = common.envOrDefault;
const makePathRecursive = common.makePathRecursive;
const readFileLimited = common.readFileLimited;
const writeFile = common.writeFile;
const writeStderr = common.writeStderr;

const DEFAULT_ETC_ROLE = "/etc/alpenglow/role";
const DEFAULT_ETC_EDITION = "/etc/alpenglow/edition";
const DEFAULT_RUN_DIR = "/run/alpenglow";

fn publishFileIfNonEmpty(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    const content = readFileLimited(allocator, src_path, 4096) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\r\n");
    if (trimmed.len == 0) return;

    const out = try std.fmt.allocPrint(allocator, "{s}\n", .{trimmed});
    defer allocator.free(out);
    try writeFile(dst_path, out, true);
}

pub fn publishRoleAndEdition(
    allocator: std.mem.Allocator,
    etc_role: []const u8,
    etc_edition: []const u8,
    run_dir: []const u8,
) !void {
    try makePathRecursive(run_dir);

    const run_role = try std.fs.path.join(allocator, &[_][]const u8{ run_dir, "role" });
    defer allocator.free(run_role);
    try publishFileIfNonEmpty(allocator, etc_role, run_role);

    const run_edition = try std.fs.path.join(allocator, &[_][]const u8{ run_dir, "edition" });
    defer allocator.free(run_edition);
    try publishFileIfNonEmpty(allocator, etc_edition, run_edition);
}

pub fn run() !void {
    const allocator = std.heap.page_allocator;
    const etc_role = envOrDefault("ALPENGLOW_ROLE_ETC_ROLE", DEFAULT_ETC_ROLE);
    const etc_edition = envOrDefault("ALPENGLOW_ROLE_ETC_EDITION", DEFAULT_ETC_EDITION);
    const run_dir = envOrDefault("ALPENGLOW_ROLE_RUN_DIR", DEFAULT_RUN_DIR);

    publishRoleAndEdition(allocator, etc_role, etc_edition, run_dir) catch |err| {
        writeStderr("alpenglow-role-publish: ");
        writeStderr(@errorName(err));
        writeStderr("\n");
        std.process.exit(1);
    };
}

test "publishRoleAndEdition copies non-empty role and edition files" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .linux) return;

    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const base_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ ".zig-cache", "tmp", &tmp.sub_path });
    defer testing.allocator.free(base_dir);

    const etc_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ base_dir, "etc" });
    defer testing.allocator.free(etc_dir);
    try makePathRecursive(etc_dir);

    const etc_role = try std.fs.path.join(testing.allocator, &[_][]const u8{ etc_dir, "role" });
    defer testing.allocator.free(etc_role);
    const etc_edition = try std.fs.path.join(testing.allocator, &[_][]const u8{ etc_dir, "edition" });
    defer testing.allocator.free(etc_edition);
    const run_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ base_dir, "run" });
    defer testing.allocator.free(run_dir);

    try writeFile(etc_role, "desktop\n", true);
    try writeFile(etc_edition, "potato\n", true);

    try publishRoleAndEdition(testing.allocator, etc_role, etc_edition, run_dir);

    const run_role = try std.fs.path.join(testing.allocator, &[_][]const u8{ run_dir, "role" });
    defer testing.allocator.free(run_role);
    const run_edition = try std.fs.path.join(testing.allocator, &[_][]const u8{ run_dir, "edition" });
    defer testing.allocator.free(run_edition);

    const role_val = try readFileLimited(testing.allocator, run_role, 256);
    defer testing.allocator.free(role_val);
    try testing.expectEqualStrings("desktop\n", role_val);

    const edition_val = try readFileLimited(testing.allocator, run_edition, 256);
    defer testing.allocator.free(edition_val);
    try testing.expectEqualStrings("potato\n", edition_val);
}

test "publishRoleAndEdition skips missing or empty files gracefully" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .linux) return;

    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const base_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ ".zig-cache", "tmp", &tmp.sub_path });
    defer testing.allocator.free(base_dir);

    const etc_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ base_dir, "etc" });
    defer testing.allocator.free(etc_dir);
    try makePathRecursive(etc_dir);

    const etc_role = try std.fs.path.join(testing.allocator, &[_][]const u8{ etc_dir, "role" });
    defer testing.allocator.free(etc_role);
    const etc_edition = try std.fs.path.join(testing.allocator, &[_][]const u8{ etc_dir, "edition" });
    defer testing.allocator.free(etc_edition);
    const run_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ base_dir, "run" });
    defer testing.allocator.free(run_dir);

    try writeFile(etc_role, "   \n", true);

    try publishRoleAndEdition(testing.allocator, etc_role, etc_edition, run_dir);

    const run_role = try std.fs.path.join(testing.allocator, &[_][]const u8{ run_dir, "role" });
    defer testing.allocator.free(run_role);
    try testing.expect(!common.fileExists(run_role));
}
