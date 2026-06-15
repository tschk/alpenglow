const std = @import("std");
const json = std.json;
const mem = std.mem;
const fs = std.fs;

const DEFAULT_POLICY = "/etc/alpenglow/kernel-policy.json";
const DEFAULT_RUNTIME_STATE = "/run/alpenglow/runtime-state.env";

const CgroupPolicy = struct {
    path: []const u8,
    cpu_weight: ?u64,
    io_weight: ?u64,
    memory_high: ?[]const u8,
    memory_max: ?[]const u8,
    pids_max: ?u64,
};

const Policy = struct {
    profile: []const u8,
    groups: []CgroupPolicy,
    sysctls: [][2][]const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aalloc = arena.allocator();

    const args = try std.process.argsAlloc(aalloc);
    var i: usize = 1;
    var policy: []const u8 = DEFAULT_POLICY;
    var runtime_state: []const u8 = DEFAULT_RUNTIME_STATE;
    var dry = false;
    var cmd_mode: enum { apply, attach } = .apply;
    var group: []const u8 = "";
    var pid: u32 = 0;

    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "attach")) {
            cmd_mode = .attach;
            while (i + 1 < args.len) {
                i += 1;
                if (mem.eql(u8, args[i], "--group")) { i += 1; group = args[i]; }
                else if (mem.eql(u8, args[i], "--pid")) { i += 1; pid = std.fmt.parseInt(u32, args[i], 10) catch 0; }
                else if (mem.eql(u8, args[i], "--dry-run")) dry = true;
            }
        } else if (mem.eql(u8, args[i], "--policy")) { i += 1; policy = args[i]; }
        else if (mem.eql(u8, args[i], "--runtime-state")) { i += 1; runtime_state = args[i]; }
        else if (mem.eql(u8, args[i], "--dry-run")) dry = true;
    }

    switch (cmd_mode) {
        .attach => {
            if (group.len == 0 or pid == 0) return;
            const cg = try std.fmt.allocPrint(aalloc, "/sys/fs/cgroup/alpenglow/{s}", .{group});
            try std.fs.cwd().makePath(cg);
            const buf = try std.fmt.allocPrint(aalloc, "{}\n", .{pid});
            writeKernelFile(cg, "cgroup.procs", buf);
        },
        .apply => {
            const raw = try fs.cwd().readFileAlloc(aalloc, policy, 1024 * 1024);
            const tree = try json.parseFromSlice(json.Value, alloc, raw, .{});
            defer tree.deinit();
            const root = tree.value;

            const profile = root.object.get("profile").?.string;
            var groups = std.ArrayList(CgroupPolicy).init(alloc);
            if (root.object.get("groups")) |arr| for (arr.array.items) |item| {
                const o = item.object;
                try groups.append(.{
                    .path = o.get("path").?.string,
                    .cpu_weight = if (o.get("cpu_weight")) |v| @intCast(v.integer) else null,
                    .io_weight = if (o.get("io_weight")) |v| @intCast(v.integer) else null,
                    .memory_high = if (o.get("memory_high")) |v| try alloc.dupe(u8, v.string) else null,
                    .memory_max = if (o.get("memory_max")) |v| try alloc.dupe(u8, v.string) else null,
                    .pids_max = if (o.get("pids_max")) |v| @intCast(v.integer) else null,
                });
            };

            var sysctls = std.ArrayList([2][]const u8).init(alloc);
            if (root.object.get("sysctl")) |obj| {
                var it = obj.object.iterator();
                while (it.next()) |e| try sysctls.append(.{ e.key_ptr.*, e.value_ptr.*.string });
            }

            if (!dry) {
                for (&[_][]const u8{ "virtio_pci", "virtio_net", "virtio_rng", "virtio_gpu" }) |m| {
                    _ = std.process.Child.run(.{ .allocator = alloc, .argv = &[_][]const u8{ "modprobe", m } }) catch {};
                }
                for (sysctls.items) |s| {
                    var p: [256]u8 = undefined;
                    @memcpy(p[0.."/proc/sys/".len], "/proc/sys/");
                    var idx: usize = "/proc/sys/".len;
                    for (s[0]) |ch| { p[idx] = if (ch == '.') '/' else ch; idx += 1; }
                    fs.cwd().writeFile(.{.sub_path = p[0..idx], .data = s[1]}) catch {};
                }
            }
            try applyCgroups(aalloc, groups.items, dry);
            try recordState(runtime_state, "ALPENGLOW_KERNEL_POLICY_FILE", policy);
            try recordState(runtime_state, "ALPENGLOW_KERNEL_POLICY_PROFILE", profile);
        },
    }
}

fn applyCgroups(alloc: mem.Allocator, groups: []CgroupPolicy, dry: bool) !void {
    const ctrl = try std.fmt.allocPrint(alloc, "/sys/fs/cgroup/cgroup.controllers", .{});
    defer alloc.free(ctrl);
    if (fs.cwd().access(ctrl, .{})) |_| {} else |_| return;
    if (dry) return;
    _ = fs.cwd().makePath("/sys/fs/cgroup/alpenglow/") catch {};
    for (groups) |g| {
        const dir = try std.fmt.allocPrint(alloc, "/sys/fs/cgroup/{s}", .{g.path});
        defer alloc.free(dir);
        fs.cwd().makePath(dir) catch {};
        try wOptU64(dir, "cpu.weight", g.cpu_weight);
        try wOptU64(dir, "io.weight", g.io_weight);
        try wOptStr(dir, "memory.high", g.memory_high);
        try wOptStr(dir, "memory.max", g.memory_max);
        try wOptU64(dir, "pids.max", g.pids_max);
    }
}

fn wOptU64(dir: []const u8, f: []const u8, v: ?u64) !void {
    if (v) |x| { var b: [32]u8 = undefined; writeKernelFile(dir, f, try std.fmt.bufPrint(&b, "{}\n", .{x})); }
}
fn wOptStr(dir: []const u8, f: []const u8, v: ?[]const u8) !void {
    if (v) |s| { var b: [256]u8 = undefined; @memcpy(b[0..s.len], s); b[s.len] = '\n'; writeKernelFile(dir, f, b[0..s.len+1]); }
}

fn writeKernelFile(dir: []const u8, file: []const u8, val: []const u8) void {
    var b: [512]u8 = undefined;
    @memcpy(b[0..dir.len], dir);
    b[dir.len] = '/';
    const rest = b[dir.len+1..];
    @memcpy(rest[0..file.len], file);
    fs.cwd().writeFile(.{.sub_path = b[0..dir.len+1+file.len], .data = val}) catch {};
}

fn recordState(path: []const u8, key: []const u8, value: []const u8) !void {
    // ponytail: write-only, don't bother reading existing state for dry-run
    if (std.fs.path.dirname(path)) |parent| _ = fs.cwd().makePath(parent) catch {};
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();
    try buf.appendSlice(key);
    try buf.append('=');
    try buf.appendSlice(value);
    try buf.append('\n');
    try fs.cwd().writeFile(.{.sub_path = path, .data = buf.items});
}
