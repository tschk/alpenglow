const std = @import("std");
const common = @import("common");
const kernel = @import("kernel");
const network = @import("network");
const pressure = @import("pressure");
const zram = @import("zram");

const MyArrayList = common.MyArrayList;
const pathToZ = common.pathToZ;
const sysOpen = common.sysOpen;
const sysRead = common.sysRead;
const sysClose = common.sysClose;
const writeStderr = common.writeStderr;

const Mode = enum {
    kernel,
    network,
    pressure,
    zram,
    help,
};

fn readCmdline(allocator: std.mem.Allocator) ![]const []const u8 {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ("/proc/self/cmdline", &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer sysClose(fd);
    var raw = MyArrayList(u8).init(allocator);
    errdefer raw.deinit();
    while (true) {
        var chunk: [4096]u8 = undefined;
        const n = try sysRead(fd, &chunk);
        if (n == 0) break;
        try raw.appendSlice(chunk[0..n]);
    }
    const data = try raw.toOwnedSlice();
    defer allocator.free(data);
    var args = MyArrayList([]const u8).init(allocator);
    errdefer args.deinit();
    var start: usize = 0;
    for (data, 0..) |byte, idx| {
        if (byte == 0) {
            try args.append(try allocator.dupe(u8, data[start..idx]));
            start = idx + 1;
        }
    }
    if (start < data.len) {
        try args.append(try allocator.dupe(u8, data[start..data.len]));
    }
    return try args.toOwnedSlice();
}

fn basenameMatches(name: []const u8, suffix: []const u8) bool {
    if (std.mem.eql(u8, name, suffix)) return true;
    return std.mem.endsWith(u8, name, suffix);
}

fn modeFromArgv0(name: []const u8) ?Mode {
    if (basenameMatches(name, "alpenglow-kernelctl") or basenameMatches(name, "kernelctl")) return .kernel;
    if (basenameMatches(name, "alpenglow-netd-zig") or basenameMatches(name, "alpenglow-netd") or basenameMatches(name, "netd")) return .network;
    if (basenameMatches(name, "alpenglow-pressurectl-zig") or basenameMatches(name, "pressurectl")) return .pressure;
    if (basenameMatches(name, "alpenglow-zramctl-zig") or basenameMatches(name, "zramctl")) return .zram;
    if (basenameMatches(name, "alpenglow-ctl")) return null;
    return null;
}

fn modeFromSubcommand(word: []const u8) ?Mode {
    if (std.mem.eql(u8, word, "kernel") or std.mem.eql(u8, word, "kernelctl")) return .kernel;
    if (std.mem.eql(u8, word, "net") or std.mem.eql(u8, word, "netd")) return .network;
    if (std.mem.eql(u8, word, "pressure") or std.mem.eql(u8, word, "pressurectl")) return .pressure;
    if (std.mem.eql(u8, word, "zram") or std.mem.eql(u8, word, "zramctl")) return .zram;
    if (std.mem.eql(u8, word, "help") or std.mem.eql(u8, word, "--help") or std.mem.eql(u8, word, "-h")) return .help;
    return null;
}

fn detectModeFromArgs(args: []const []const u8) Mode {
    if (args.len == 0) return .help;

    const exe = std.fs.path.basename(args[0]);
    if (modeFromArgv0(exe)) |mode| return mode;

    if (args.len >= 2) {
        if (modeFromSubcommand(args[1])) |mode| return mode;
    }

    return .help;
}

fn detectMode(allocator: std.mem.Allocator) !Mode {
    const args = try readCmdline(allocator);
    return detectModeFromArgs(args);
}

test "detectModeFromArgs argv0 matching" {
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{"alpenglow-kernelctl"}));
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{"/usr/bin/kernelctl"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"alpenglow-netd-zig"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"alpenglow-netd"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"netd"}));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{"/sbin/pressurectl"}));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{"zramctl"}));
}

test "detectModeFromArgs subcommand matching" {
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "kernel"}));
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "kernelctl"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "net"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "netd"}));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "pressure"}));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "pressurectl"}));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "zram"}));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "zramctl"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "help"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "--help"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "-h"}));
}

test "detectModeFromArgs fallbacks and invalid inputs" {
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"unknown-program"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "invalid"}));
}

fn printHelp() void {
    writeStderr(
        \\alpenglow-ctl: kernel, network, pressure, and zram policy daemons
        \\usage:
        \\  alpenglow-ctl <kernel|net|pressure|zram> [args...]
        \\  alpenglow-kernelctl [apply|attach ...]
        \\  alpenglow-netd-zig
        \\  alpenglow-pressurectl-zig
        \\  alpenglow-zramctl-zig
        \\
    );
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const mode = detectMode(allocator) catch .help;
    switch (mode) {
        .kernel => try kernel.run(),
        .network => try network.run(),
        .pressure => try pressure.run(),
        .zram => try zram.run(),
        .help => {
            printHelp();
            std.process.exit(2);
        },
    }
}
