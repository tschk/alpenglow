const std = @import("std");

const ZRAM_CONTROL = "/sys/class/zram-control";
const ZRAM0 = "/sys/block/zram0";
const ZRAM0_DEV = "/dev/zram0";
const MEMINFO = "/proc/meminfo";

fn fileExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn readMemTotalKb(io: std.Io, gpa: std.mem.Allocator) !u64 {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, MEMINFO, gpa, .unlimited);
    defer gpa.free(content);
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

fn writeZramDisksize(io: std.Io, size_kb: u64) !void {
    const path = ZRAM0 ++ "/disksize";
    const value = try std.fmt.allocPrint(std.heap.page_allocator, "{d}K", .{size_kb});
    defer std.heap.page_allocator.free(value);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = value });
}

fn hotAddZram(io: std.Io) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = ZRAM_CONTROL ++ "/hot_add", .data = "1" });
}

fn spawnAndWait(io: std.Io, argv: []const []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0 and code != 255) return error.ChildProcessFailed,
        else => return error.ChildProcessFailed,
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    if (!fileExists(io, ZRAM_CONTROL)) {
        std.Io.File.stderr().writeStreamingAll(io, "zramctl: zram-control not available\n") catch {};
        std.process.exit(1);
    }

    if (!fileExists(io, ZRAM0)) {
        hotAddZram(io) catch |err| {
            std.Io.File.stderr().writeStreamingAll(io, "zramctl: hot_add failed: ") catch {};
            std.Io.File.stderr().writeStreamingAll(io, @errorName(err)) catch {};
            std.Io.File.stderr().writeStreamingAll(io, "\n") catch {};
            std.process.exit(1);
        };
    }

    const mem_kb = readMemTotalKb(io, gpa) catch |err| {
        std.Io.File.stderr().writeStreamingAll(io, "zramctl: cannot read MemTotal: ") catch {};
        std.Io.File.stderr().writeStreamingAll(io, @errorName(err)) catch {};
        std.Io.File.stderr().writeStreamingAll(io, "\n") catch {};
        std.process.exit(1);
    };
    const size_kb = mem_kb / 2;
    if (size_kb == 0) {
        std.Io.File.stderr().writeStreamingAll(io, "zramctl: zero memory, aborting\n") catch {};
        std.process.exit(1);
    }

    writeZramDisksize(io, size_kb) catch |err| {
        std.Io.File.stderr().writeStreamingAll(io, "zramctl: cannot set disksize: ") catch {};
        std.Io.File.stderr().writeStreamingAll(io, @errorName(err)) catch {};
        std.Io.File.stderr().writeStreamingAll(io, "\n") catch {};
        std.process.exit(1);
    };

    if (fileExists(io, "/usr/sbin/mkswap") and fileExists(io, "/usr/sbin/swapon")) {
        spawnAndWait(io, &.{ "/usr/sbin/mkswap", ZRAM0_DEV }) catch {};
        spawnAndWait(io, &.{ "/usr/sbin/swapon", ZRAM0_DEV }) catch {};
    }
}
