const std = @import("std");
const common = @import("common");
const kernel = @import("kernel");
const logrotate = @import("logrotate");
const network = @import("network");
const power = @import("power");
const pressure = @import("pressure");
const role = @import("role");
const state = @import("state");
const zram = @import("zram");

const readCmdline = common.readCmdline;
const writeStderr = common.writeStderr;

const Mode = enum {
    kernel,
    logrotate,
    network,
    power,
    pressure,
    role,
    state,
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
    if (basenameMatches(name, "alpenglow-pressurectl-zig") or basenameMatches(name, "alpenglow-pressurectl") or basenameMatches(name, "pressurectl")) return .pressure;
    if (basenameMatches(name, "alpenglow-zramctl-zig") or basenameMatches(name, "alpenglow-zramctl") or basenameMatches(name, "zramctl")) return .zram;
    if (basenameMatches(name, "alpenglow-role-publish") or basenameMatches(name, "alpenglow-rolectl")) return .role;
    if (basenameMatches(name, "alpenglow-power.sh") or basenameMatches(name, "alpenglow-powerctl") or basenameMatches(name, "alpenglow-power")) return .power;
    if (basenameMatches(name, "logrotate.sh") or basenameMatches(name, "alpenglow-logrotate")) return .logrotate;
    if (basenameMatches(name, "mount-state.sh") or basenameMatches(name, "alpenglow-state-mount") or basenameMatches(name, "alpenglow-statectl")) return .state;
    if (basenameMatches(name, "alpenglow-ctl")) return null;
    return null;
}

fn modeFromSubcommand(word: []const u8) ?Mode {
    if (std.mem.eql(u8, word, "kernel") or std.mem.eql(u8, word, "kernelctl")) return .kernel;
    if (std.mem.eql(u8, word, "net") or std.mem.eql(u8, word, "netd")) return .network;
    if (std.mem.eql(u8, word, "pressure") or std.mem.eql(u8, word, "pressurectl")) return .pressure;
    if (std.mem.eql(u8, word, "zram") or std.mem.eql(u8, word, "zramctl")) return .zram;
    if (std.mem.eql(u8, word, "role") or std.mem.eql(u8, word, "rolectl") or std.mem.eql(u8, word, "role-publish")) return .role;
    if (std.mem.eql(u8, word, "power") or std.mem.eql(u8, word, "powerctl")) return .power;
    if (std.mem.eql(u8, word, "logrotate")) return .logrotate;
    if (std.mem.eql(u8, word, "state") or std.mem.eql(u8, word, "state-mount") or std.mem.eql(u8, word, "mount-state")) return .state;
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

fn subcommandTailArgs(args: []const []const u8) []const []const u8 {
    if (args.len == 0) return &.{};
    const exe = std.fs.path.basename(args[0]);
    if (modeFromArgv0(exe) != null) {
        return args[1..];
    }
    if (args.len >= 2) {
        return args[2..];
    }
    return &.{};
}

test "detectModeFromArgs argv0 matching" {
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{"alpenglow-kernelctl"}));
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{"/usr/bin/kernelctl"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"alpenglow-netd-zig"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"alpenglow-netd"}));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{"netd"}));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{"/sbin/pressurectl"}));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{"alpenglow-pressurectl"}));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{"zramctl"}));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{"alpenglow-zramctl"}));
    try std.testing.expectEqual(Mode.role, detectModeFromArgs(&[_][]const u8{"/usr/local/bin/alpenglow-role-publish"}));
    try std.testing.expectEqual(Mode.power, detectModeFromArgs(&[_][]const u8{"/usr/local/bin/alpenglow-power.sh"}));
    try std.testing.expectEqual(Mode.power, detectModeFromArgs(&[_][]const u8{"alpenglow-powerctl"}));
    try std.testing.expectEqual(Mode.logrotate, detectModeFromArgs(&[_][]const u8{"/usr/local/bin/logrotate.sh"}));
    try std.testing.expectEqual(Mode.logrotate, detectModeFromArgs(&[_][]const u8{"alpenglow-logrotate"}));
    try std.testing.expectEqual(Mode.state, detectModeFromArgs(&[_][]const u8{"/usr/local/bin/mount-state.sh"}));
    try std.testing.expectEqual(Mode.state, detectModeFromArgs(&[_][]const u8{"alpenglow-state-mount"}));
}

test "detectModeFromArgs subcommand matching" {
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "kernel" }));
    try std.testing.expectEqual(Mode.kernel, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "kernelctl" }));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "net" }));
    try std.testing.expectEqual(Mode.network, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "netd" }));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "pressure" }));
    try std.testing.expectEqual(Mode.pressure, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "pressurectl" }));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "zram" }));
    try std.testing.expectEqual(Mode.zram, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "zramctl" }));
    try std.testing.expectEqual(Mode.role, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "role" }));
    try std.testing.expectEqual(Mode.role, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "role-publish" }));
    try std.testing.expectEqual(Mode.power, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "power" }));
    try std.testing.expectEqual(Mode.power, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "powerctl" }));
    try std.testing.expectEqual(Mode.logrotate, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "logrotate" }));
    try std.testing.expectEqual(Mode.state, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "state" }));
    try std.testing.expectEqual(Mode.state, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "state-mount" }));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "help" }));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "--help" }));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "-h" }));
}

test "detectModeFromArgs fallbacks and invalid inputs" {
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"alpenglow-ctl"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{"unknown-program"}));
    try std.testing.expectEqual(Mode.help, detectModeFromArgs(&[_][]const u8{ "alpenglow-ctl", "invalid" }));
}

fn printHelp() void {
    writeStderr(
        \\alpenglow-ctl: kernel, network, pressure, zram, role, power, state, and logrotate multicall daemon
        \\usage:
        \\  alpenglow-ctl <kernel|net|pressure|zram|role|power|state|logrotate> [args...]
        \\  alpenglow-kernelctl [apply|attach ...]
        \\  alpenglow-netd
        \\  alpenglow-pressurectl
        \\  alpenglow-zramctl
        \\  alpenglow-role-publish
        \\  alpenglow-powerctl [suspend|hibernate|hybrid|status]
        \\  alpenglow-state-mount
        \\  alpenglow-logrotate
        \\
    );
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = readCmdline(allocator) catch &[_][]const u8{};
    const mode = detectModeFromArgs(args);
    switch (mode) {
        .kernel => try kernel.run(),
        .logrotate => try logrotate.run(),
        .network => try network.run(),
        .power => try power.runWithArgs(subcommandTailArgs(args)),
        .pressure => try pressure.run(),
        .role => try role.run(),
        .state => try state.run(),
        .zram => try zram.run(),
        .help => {
            printHelp();
            std.process.exit(2);
        },
    }
}

test "modeFromSubcommand returns correct modes" {
    const testing = std.testing;

    // kernel
    try testing.expectEqual(Mode.kernel, modeFromSubcommand("kernel"));
    try testing.expectEqual(Mode.kernel, modeFromSubcommand("kernelctl"));

    // network
    try testing.expectEqual(Mode.network, modeFromSubcommand("net"));
    try testing.expectEqual(Mode.network, modeFromSubcommand("netd"));

    // pressure
    try testing.expectEqual(Mode.pressure, modeFromSubcommand("pressure"));
    try testing.expectEqual(Mode.pressure, modeFromSubcommand("pressurectl"));

    // zram
    try testing.expectEqual(Mode.zram, modeFromSubcommand("zram"));
    try testing.expectEqual(Mode.zram, modeFromSubcommand("zramctl"));

    // role / power / logrotate / state
    try testing.expectEqual(Mode.role, modeFromSubcommand("role"));
    try testing.expectEqual(Mode.role, modeFromSubcommand("role-publish"));
    try testing.expectEqual(Mode.power, modeFromSubcommand("power"));
    try testing.expectEqual(Mode.power, modeFromSubcommand("powerctl"));
    try testing.expectEqual(Mode.logrotate, modeFromSubcommand("logrotate"));
    try testing.expectEqual(Mode.state, modeFromSubcommand("state"));
    try testing.expectEqual(Mode.state, modeFromSubcommand("state-mount"));

    // help
    try testing.expectEqual(Mode.help, modeFromSubcommand("help"));
    try testing.expectEqual(Mode.help, modeFromSubcommand("--help"));
    try testing.expectEqual(Mode.help, modeFromSubcommand("-h"));

    // null / invalid
    try testing.expectEqual(@as(?Mode, null), modeFromSubcommand("unknown"));
    try testing.expectEqual(@as(?Mode, null), modeFromSubcommand(""));
}

test "modeFromArgv0" {
    const testing = std.testing;

    try testing.expectEqual(Mode.kernel, modeFromArgv0("alpenglow-kernelctl"));
    try testing.expectEqual(Mode.kernel, modeFromArgv0("kernelctl"));
    try testing.expectEqual(Mode.kernel, modeFromArgv0("/usr/bin/kernelctl"));

    try testing.expectEqual(Mode.network, modeFromArgv0("alpenglow-netd-zig"));
    try testing.expectEqual(Mode.network, modeFromArgv0("alpenglow-netd"));
    try testing.expectEqual(Mode.network, modeFromArgv0("netd"));

    try testing.expectEqual(Mode.pressure, modeFromArgv0("alpenglow-pressurectl-zig"));
    try testing.expectEqual(Mode.pressure, modeFromArgv0("alpenglow-pressurectl"));
    try testing.expectEqual(Mode.pressure, modeFromArgv0("pressurectl"));

    try testing.expectEqual(Mode.zram, modeFromArgv0("alpenglow-zramctl-zig"));
    try testing.expectEqual(Mode.zram, modeFromArgv0("alpenglow-zramctl"));
    try testing.expectEqual(Mode.zram, modeFromArgv0("zramctl"));

    try testing.expectEqual(Mode.role, modeFromArgv0("alpenglow-role-publish"));
    try testing.expectEqual(Mode.power, modeFromArgv0("alpenglow-power.sh"));
    try testing.expectEqual(Mode.power, modeFromArgv0("alpenglow-powerctl"));
    try testing.expectEqual(Mode.logrotate, modeFromArgv0("logrotate.sh"));
    try testing.expectEqual(Mode.logrotate, modeFromArgv0("alpenglow-logrotate"));
    try testing.expectEqual(Mode.state, modeFromArgv0("mount-state.sh"));
    try testing.expectEqual(Mode.state, modeFromArgv0("alpenglow-state-mount"));

    try testing.expectEqual(@as(?Mode, null), modeFromArgv0("alpenglow-ctl"));
    try testing.expectEqual(@as(?Mode, null), modeFromArgv0("unknownctl"));
}
