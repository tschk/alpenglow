const std = @import("std");
const linux = std.os.linux;
const common = @import("common");

const MyArrayList = common.MyArrayList;
const envOrDefault = common.envOrDefault;
const fileExists = common.fileExists;
const getErrno = common.getErrno;
const makePathRecursive = common.makePathRecursive;
const pathToZ = common.pathToZ;
const readFileLimited = common.readFileLimited;
const writeStderr = common.writeStderr;

const DEFAULT_CMDLINE_PATH = "/proc/cmdline";
const DEFAULT_MOUNTS_PATH = "/proc/mounts";
const DEFAULT_STATE_ROOT = "/state";

pub const StateConfig = struct {
    state_dev: []const u8 = "LABEL=alpenglow-state",
    encrypted: bool = false,
    key_path: ?[]const u8 = null,
};

pub fn isValidKeyPath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    return true;
}

pub fn parseCmdlineStateConfig(cmdline: []const u8) StateConfig {
    var cfg = StateConfig{};
    var it = std.mem.tokenizeAny(u8, cmdline, " \t\r\n");
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "alpenglow.state=")) {
            const val = arg["alpenglow.state=".len..];
            if (val.len > 0) cfg.state_dev = val;
        } else if (std.mem.startsWith(u8, arg, "alpenglow.state.encrypted=")) {
            const val = arg["alpenglow.state.encrypted=".len..];
            cfg.encrypted = std.mem.eql(u8, val, "1");
        } else if (std.mem.startsWith(u8, arg, "alpenglow.state.key=")) {
            const val = arg["alpenglow.state.key=".len..];
            if (val.len > 0) cfg.key_path = val;
        }
    }
    return cfg;
}

pub fn isStateMounted(mounts_content: []const u8, mount_point: []const u8) bool {
    var lines = std.mem.splitScalar(u8, mounts_content, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        _ = fields.next() orelse continue; // device
        const target = fields.next() orelse continue;
        if (std.mem.eql(u8, target, mount_point)) return true;
    }
    return false;
}

pub const STATE_SUBDIRS = [_][]const u8{
    "home",
    "var/lib/alpenglow/browser/profiles",
    "var/lib/alpenglow/browser/cache",
    "var/lib/alpenglow/browser/downloads",
    "var/lib/alpenglow/browser/state",
    "var/lib/alpenglow/browser/logs",
    "var/lib/alpenglow/browser/terminal",
    "var/lib/alpenglow/files",
    "var/lib/alpenglow/system",
    "var/lib/alpenglow/system/plugins",
    "var/lib/alpenglow/oil",
    "var/cache/alpenglow",
    "var/log/alpenglow",
};

pub const BIND_MOUNTS = [_][2][]const u8{
    .{ "/state/home", "/home" },
    .{ "/state/var/lib/alpenglow", "/var/lib/alpenglow" },
    .{ "/state/var/cache/alpenglow", "/var/cache/alpenglow" },
    .{ "/state/var/log/alpenglow", "/var/log/alpenglow" },
};

pub fn ensureStateDirectories(allocator: std.mem.Allocator, state_root: []const u8) !void {
    for (STATE_SUBDIRS) |sub| {
        const dir = try std.fs.path.join(allocator, &[_][]const u8{ state_root, sub });
        defer allocator.free(dir);
        makePathRecursive(dir) catch {};
    }
}

fn sysMountBind(source: []const u8, target: []const u8) void {
    var src_buf: [4096]u8 = undefined;
    var tgt_buf: [4096]u8 = undefined;
    const src_z = pathToZ(source, &src_buf) orelse return;
    const tgt_z = pathToZ(target, &tgt_buf) orelse return;
    const fstype_z: [*:0]const u8 = "none";
    _ = linux.mount(src_z.ptr, tgt_z.ptr, fstype_z, linux.MS.BIND, 0);
}

fn spawnCommand(argv: []const []const u8) !void {
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
    const env_array = &[_:null]?[*:0]const u8{
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        null,
    };

    const pid = linux.fork();
    if (pid == 0) {
        _ = linux.execve(arg_ptrs[0].?, &arg_ptrs, env_array);
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
        if (linux.W.EXITSTATUS(status) != 0) return error.ChildProcessFailed;
    }
}

fn resolveStateBlockDev(allocator: std.mem.Allocator, spec: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, spec, "LABEL=")) {
        const label = spec["LABEL=".len..];
        const by_label = try std.fmt.allocPrint(allocator, "/dev/disk/by-label/{s}", .{label});
        if (fileExists(by_label)) return by_label;
        allocator.free(by_label);
    }
    return allocator.dupe(u8, spec);
}

pub fn run() !void {
    const allocator = std.heap.page_allocator;
    const cmdline_path = envOrDefault("ALPENGLOW_CMDLINE_PATH", DEFAULT_CMDLINE_PATH);
    const mounts_path = envOrDefault("ALPENGLOW_MOUNTS_PATH", DEFAULT_MOUNTS_PATH);
    const state_root = envOrDefault("ALPENGLOW_STATE_ROOT", DEFAULT_STATE_ROOT);

    const cmdline = readFileLimited(allocator, cmdline_path, 4096) catch "";
    defer if (cmdline.len > 0) allocator.free(cmdline);
    const cfg = parseCmdlineStateConfig(cmdline);

    if (cfg.key_path) |key| {
        if (!isValidKeyPath(key)) {
            writeStderr("alpenglow-state-mount: invalid key path\n");
            std.process.exit(1);
        }
    }

    const mounts = readFileLimited(allocator, mounts_path, 65536) catch "";
    defer if (mounts.len > 0) allocator.free(mounts);

    if (!isStateMounted(mounts, state_root)) {
        // If LUKS or complex blkid probing is required and /usr/local/bin/mount-state.sh exists,
        // delegate the initial block mount or mount directly via /bin/mount.
        const resolved = try resolveStateBlockDev(allocator, cfg.state_dev);
        defer allocator.free(resolved);

        const mount_bin = if (fileExists("/bin/mount")) "/bin/mount" else "/usr/bin/mount";
        spawnCommand(&[_][]const u8{
            mount_bin,
            "-t",
            "bcachefs",
            "-o",
            "rw,nosuid,nodev",
            resolved,
            state_root,
        }) catch {
            writeStderr("alpenglow-state-mount: bcachefs state mount failed\n");
            std.process.exit(1);
        };
    }

    try ensureStateDirectories(allocator, state_root);

    if (std.mem.eql(u8, state_root, "/state")) {
        for (BIND_MOUNTS) |pair| {
            makePathRecursive(pair[1]) catch {};
            sysMountBind(pair[0], pair[1]);
        }
    }
}

test "isValidKeyPath rejects traversal and relative paths" {
    const testing = std.testing;
    try testing.expect(isValidKeyPath("/etc/alpenglow/state.key"));
    try testing.expect(isValidKeyPath("/run/secrets/key"));
    try testing.expect(!isValidKeyPath(""));
    try testing.expect(!isValidKeyPath("relative/key"));
    try testing.expect(!isValidKeyPath("/etc/../shadow"));
}

test "parseCmdlineStateConfig extracts state arguments" {
    const testing = std.testing;
    const cfg = parseCmdlineStateConfig("quiet alpenglow.state=/dev/vda2 alpenglow.state.encrypted=1 alpenglow.state.key=/etc/keyfile\n");
    try testing.expectEqualStrings("/dev/vda2", cfg.state_dev);
    try testing.expect(cfg.encrypted);
    try testing.expectEqualStrings("/etc/keyfile", cfg.key_path.?);

    const def = parseCmdlineStateConfig("console=ttyS0 quiet");
    try testing.expectEqualStrings("LABEL=alpenglow-state", def.state_dev);
    try testing.expect(!def.encrypted);
    try testing.expectEqual(@as(?[]const u8, null), def.key_path);
}

test "isStateMounted detects /state mount point" {
    const testing = std.testing;
    const sample_mounts =
        \\proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
        \\/dev/vda2 /state bcachefs rw,nosuid,nodev,relatime 0 0
        \\tmpfs /run tmpfs rw,nosuid,nodev,mode=755 0 0
    ;
    try testing.expect(isStateMounted(sample_mounts, "/state"));
    try testing.expect(!isStateMounted(sample_mounts, "/mnt"));
}

test "ensureStateDirectories creates expected state layout" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .linux) return;

    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const state_root = try std.fs.path.join(testing.allocator, &[_][]const u8{ ".zig-cache", "tmp", &tmp.sub_path, "state" });
    defer testing.allocator.free(state_root);

    try ensureStateDirectories(testing.allocator, state_root);

    const oil_dir = try std.fs.path.join(testing.allocator, &[_][]const u8{ state_root, "var/lib/alpenglow/oil" });
    defer testing.allocator.free(oil_dir);
    try testing.expect(fileExists(oil_dir));
}
