const std = @import("std");

const Mode = enum {
    kernel,
    network,
    pressure,
    zram,
    help,
};

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

test "detectModeFromArgs" {
    try std.testing.expectEqual(.help, detectModeFromArgs(&[_][]const u8{}));

    try std.testing.expectEqual(.kernel, detectModeFromArgs(&[_][]const u8{"alpenglow-kernelctl"}));
    try std.testing.expectEqual(.kernel, detectModeFromArgs(&[_][]const u8{"/usr/bin/kernelctl"}));
    try std.testing.expectEqual(.network, detectModeFromArgs(&[_][]const u8{"netd"}));
    try std.testing.expectEqual(.pressure, detectModeFromArgs(&[_][]const u8{"alpenglow-pressurectl-zig"}));
    try std.testing.expectEqual(.zram, detectModeFromArgs(&[_][]const u8{"zramctl"}));

    try std.testing.expectEqual(.kernel, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "kernel"}));
    try std.testing.expectEqual(.network, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "net"}));
    try std.testing.expectEqual(.pressure, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "pressurectl"}));
    try std.testing.expectEqual(.zram, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "zram"}));

    try std.testing.expectEqual(.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "help"}));
    try std.testing.expectEqual(.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "--help"}));
    try std.testing.expectEqual(.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "-h"}));

    try std.testing.expectEqual(.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl", "unknown"}));
    try std.testing.expectEqual(.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl"}));
}
