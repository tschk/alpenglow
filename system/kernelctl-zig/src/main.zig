const std = @import("std");
const json = std.json;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const process = std.process;

const DEFAULT_POLICY = "/etc/alpenglow/kernel-policy.json";
const DEFAULT_RUNTIME_STATE = "/run/alpenglow/runtime-state.env";
const DEFAULT_CGROUP_FS = "/sys/fs/cgroup";

const Command = union(enum) {
    apply: void,
    attach: struct { group: []const u8, pid: u32 },
};

const Args = struct {
    command: Command = .{ .apply = {} },
    policy: []const u8 = DEFAULT_POLICY,
    runtime_state: []const u8 = DEFAULT_RUNTIME_STATE,
    cgroup_fs: []const u8 = DEFAULT_CGROUP_FS,
    dry_run: bool = false,

    fn parse(alloc: mem.Allocator) !Args {
        var args = Args{};
        var i: usize = 0;
        while (i < process.args.len) : (i += 1) {
            const arg = process.args[i];
            if (mem.eql(u8, arg, "apply")) {
                args.command = .{ .apply = {} };
            } else if (mem.eql(u8, arg, "attach")) {
                var group: []const u8 = "";
                var pid: u32 = 0;
                while (i + 1 < process.args.len) {
                    i += 1;
                    const val = process.args[i];
                    if (mem.eql(u8, val, "--group")) {
                        if (i + 1 < process.args.len) {
                            i += 1;
                            group = try alloc.dupe(u8, process.args[i]);
                        }
                    } else if (mem.eql(u8, val, "--pid")) {
                        if (i + 1 < process.args.len) {
                            i += 1;
                            pid = try std.fmt.parseInt(u32, process.args[i], 10);
                        }
                    } else if (mem.eql(u8, val, "--cgroup-fs")) {
                        if (i + 1 < process.args.len) {
                            i += 1;
                            args.cgroup_fs = try alloc.dupe(u8, process.args[i]);
                        }
                    } else if (mem.eql(u8, val, "--dry-run")) {
                        args.dry_run = true;
                    }
                }
                args.command = .{ .attach = .{ .group = group, .pid = pid } };
                break;
            } else if (mem.eql(u8, arg, "--policy")) {
                if (i + 1 < process.args.len) {
                    i += 1;
                    args.policy = try alloc.dupe(u8, process.args[i]);
                }
            } else if (mem.eql(u8, arg, "--runtime-state")) {
                if (i + 1 < process.args.len) {
                    i += 1;
                    args.runtime_state = try alloc.dupe(u8, process.args[i]);
                }
            } else if (mem.eql(u8, arg, "--cgroup-fs")) {
                if (i + 1 < process.args.len) {
                    i += 1;
                    args.cgroup_fs = try alloc.dupe(u8, process.args[i]);
                }
            } else if (mem.eql(u8, arg, "--dry-run")) {
                args.dry_run = true;
            }
        }
        return args;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const args = Args.parse(alloc) catch |e| {
        std.log.err("parse args: {s}", .{@errorName(e)});
        process.exit(1);
    };

    run(arena_alloc, args) catch |e| {
        std.log.err("{s}", .{@errorName(e)});
        process.exit(1);
    };
}

fn run(alloc: mem.Allocator, args: Args) !void {
    switch (args.command) {
        .attach => |a| {
            if (a.group.len == 0 or a.pid == 0) return;
            const cg = try std.fmt.allocPrint(alloc, "{s}/alpenglow/{s}", .{ args.cgroup_fs, a.group });
            defer alloc.free(cg);
            try writeCgroupFile(alloc, cg, "cgroup.procs", try std.fmt.allocPrint(alloc, "{}", .{a.pid}), args.dry_run);
        },
        .apply => {
            const policy_raw = readFile(alloc, args.policy) catch |e| {
                std.log.err("read policy: {s}", .{@errorName(e)});
                process.exit(1);
            };
            const policy = parsePolicy(alloc, policy_raw) catch |e| {
                std.log.err("parse policy: {s}", .{@errorName(e)});
                process.exit(1);
            };

            loadKernelModules(args.dry_run);
            applySysctls(alloc, policy.sysctls, args.dry_run) catch |e| {
                std.log.err("sysctl: {s}", .{@errorName(e)});
            };
            const cg_state = applyCgroups(alloc, args.cgroup_fs, policy.groups, args.dry_run) catch |e| {
                std.log.err("cgroup: {s}", .{@errorName(e)});
                "error"
            };

            try recordState(args.runtime_state, "ALPENGLOW_KERNEL_POLICY_FILE", args.policy);
            try recordState(args.runtime_state, "ALPENGLOW_KERNEL_POLICY_CGROUPS", cg_state);
            try recordState(args.runtime_state, "ALPENGLOW_KERNEL_POLICY_PROFILE", policy.profile);
        },
    }
}

const Policy = struct {
    profile: []const u8,
    groups: []CgroupPolicy,
    sysctls: []SysctlEntry,
};

const CgroupPolicy = struct {
    path: []const u8,
    cpu_weight: ?u64,
    io_weight: ?u64,
    memory_high: ?[]const u8,
    memory_max: ?[]const u8,
    pids_max: ?u64,
};

const SysctlEntry = struct {
    key: []const u8,
    value: []const u8,
};

fn parsePolicy(alloc: mem.Allocator, raw: []const u8) !Policy {
    const tree = try json.parseFromSlice(json.Value, alloc, raw, .{});
    const root = tree.value;

    var profile: []const u8 = "";
    if (root.object.get("profile")) |v| profile = v.string;

    var groups = std.ArrayList(CgroupPolicy).init(alloc);
    if (root.object.get("groups")) |arr| {
        for (arr.array.items) |item| {
            groups.append(try parseCgroup(alloc, item)) catch {};
        }
    }

    var sysctls = std.ArrayList(SysctlEntry).init(alloc);
    if (root.object.get("sysctl")) |obj| {
        var it = obj.object.iterator();
        while (it.next()) |entry| {
            sysctls.append(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.*.string }) catch {};
        }
    }

    return Policy{
        .profile = profile,
        .groups = try groups.toOwnedSlice(),
        .sysctls = try sysctls.toOwnedSlice(),
    };
}

fn parseCgroup(alloc: mem.Allocator, val: json.Value) !CgroupPolicy {
    var cg = CgroupPolicy{
        .path = "",
        .cpu_weight = null,
        .io_weight = null,
        .memory_high = null,
        .memory_max = null,
        .pids_max = null,
    };
    const obj = val.object;
    if (obj.get("path")) |v| cg.path = try alloc.dupe(u8, v.string);
    if (obj.get("cpu_weight")) |v| cg.cpu_weight = @intCast(v.integer);
    if (obj.get("io_weight")) |v| cg.io_weight = @intCast(v.integer);
    if (obj.get("memory_high")) |v| cg.memory_high = try alloc.dupe(u8, v.string);
    if (obj.get("memory_max")) |v| cg.memory_max = try alloc.dupe(u8, v.string);
    if (obj.get("pids_max")) |v| cg.pids_max = @intCast(v.integer);
    return cg;
}

fn loadKernelModules(dry_run: bool) void {
    if (dry_run) return;
    for (&[_][]const u8{ "virtio_pci", "virtio_net", "virtio_rng", "virtio_gpu" }) |mod| {
        _ = process.Child.run(.{ .allocator = std.heap.page_allocator, .argv = &[_][]const u8{ "modprobe", mod } }) catch {};
    }
}

fn applySysctls(alloc: mem.Allocator, entries: []SysctlEntry, dry_run: bool) !void {
    for (entries) |e| {
        var path_buf: [256]u8 = undefined;
        var idx: usize = 0;
        const prefix = "/proc/sys/";
        @memcpy(path_buf[0..prefix.len], prefix);
        idx = prefix.len;
        // ponytail: dot-to-slash replace in place
        for (e.key) |ch| {
            path_buf[idx] = if (ch == '.') '/' else ch;
            idx += 1;
        }
        path_buf[idx] = 0;
        const path = path_buf[0..idx :0];
        if (!dry_run) {
            writeFile(path, e.value) catch {};
        }
    }
}

fn applyCgroups(alloc: mem.Allocator, cgroup_fs: []const u8, groups: []CgroupPolicy, dry_run: bool) ![]const u8 {
    const ctrl_path = try std.fmt.allocPrint(alloc, "{s}/cgroup.controllers", .{cgroup_fs});
    defer alloc.free(ctrl_path);
    if (access(ctrl_path)) return "unavailable";
    if (dry_run) return "active";

    // ponytail: single alpenglow root, no nested hierarchy
    const root_path = try std.fmt.allocPrint(alloc, "{s}/alpenglow", .{cgroup_fs});
    defer alloc.free(root_path);
    makeDir(root_path) catch {};

    // enable controllers
    const sub = try std.fmt.allocPrint(alloc, "{s}/cgroup.subtree_control", .{cgroup_fs});
    defer alloc.free(sub);
    for (&[_][]const u8{ "+cpu\n", "+io\n", "+memory\n", "+pids\n" }) |ctl| {
        writeFile(sub, ctl) catch {};
    }

    for (groups) |g| {
        const dir = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ cgroup_fs, g.path });
        defer alloc.free(dir);
        makeDir(dir) catch {};
        try writeOptionalU64(dir, "cpu.weight", g.cpu_weight);
        try writeOptionalU64(dir, "io.weight", g.io_weight);
        try writeOptionalStr(dir, "memory.high", g.memory_high);
        try writeOptionalStr(dir, "memory.max", g.memory_max);
        try writeOptionalU64(dir, "pids.max", g.pids_max);
    }
    return "active";
}

fn writeOptionalU64(dir: []const u8, file: []const u8, val: ?u64) !void {
    if (val) |v| {
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{}\n", .{v});
        writeKernelFile(dir, file, s) catch {};
    }
}

fn writeOptionalStr(dir: []const u8, file: []const u8, val: ?[]const u8) !void {
    if (val) |v| {
        const s = try std.fmt.allocPrint(std.heap.page_allocator, "{s}\n", .{v});
        defer std.heap.page_allocator.free(s);
        writeKernelFile(dir, file, s) catch {};
    }
}

fn writeCgroupFile(alloc: mem.Allocator, dir: []const u8, file: []const u8, val: []const u8, dry_run: bool) !void {
    if (dry_run) return;
    makeDir(dir) catch {};
    writeKernelFile(dir, file, val) catch {};
}

fn writeKernelFile(dir: []const u8, file: []const u8, val: []const u8) !void {
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ dir, file });
    defer std.heap.page_allocator.free(path);
    writeFile(path, val) catch |e| switch (e) {
        error.AccessDenied, error.FileNotFound => return,
        else => return e,
    };
}

fn recordState(path: []const u8, key: []const u8, value: []const u8) !void {
    // ponytail: read-modify-write, simple line-by-line env file
    var entries = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    defer entries.deinit();

    if (readFile(std.heap.page_allocator, path)) |raw| {
        defer std.heap.page_allocator.free(raw);
        var lines = mem.tokenizeScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            if (mem.indexOfScalar(u8, line, '=')) |eq| {
                const k = line[0..eq];
                const v = line[eq + 1 ..];
                entries.put(k, v) catch {};
            }
        }
    } else |_| {}

    entries.put(key, value) catch {};

    // write back
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    var it = entries.iterator();
    while (it.next()) |entry| {
        buf.appendSlice(entry.key_ptr.*) catch {};
        _ = buf.append('=') catch {};
        buf.appendSlice(entry.value_ptr.*) catch {};
        _ = buf.append('\n') catch {};
    }
    const parent = fs.path.dirname(path) orelse ".";
    makeDir(parent) catch {};
    writeFile(path, buf.items) catch {};
}

// helpers

fn readFile(alloc: mem.Allocator, path: []const u8) ![]u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(alloc, 1024 * 1024);
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

fn makeDir(path: []const u8) !void {
    fs.cwd().makePath(path) catch |e| switch (e) {
        error.PathAlreadyExists => return,
        else => return e,
    };
}

fn access(path: []const u8) bool {
    fs.cwd().access(path, .{}) catch return false;
    return true;
}
