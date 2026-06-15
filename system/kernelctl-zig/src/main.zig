const std = @import("std");
const mem = std.mem;

const DFL_POL = "/etc/alpenglow/kernel-policy.json";
const DFL_RUN = "/run/alpenglow/runtime-state.env";

const CgPol = struct {
    path: []const u8,
    cpu_weight: ?u64,
    io_weight: ?u64,
    memory_high: ?[]const u8,
    memory_max: ?[]const u8,
    pids_max: ?u64,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    var i: usize = 1;
    var policy: []const u8 = DFL_POL;
    var run: []const u8 = DFL_RUN;
    var dry = false;
    var cmd: enum { apply, attach } = .apply;
    var group: []const u8 = "";
    var pid: u32 = 0;

    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "attach")) {
            cmd = .attach;
            while (i + 1 < args.len) {
                i += 1;
                if (mem.eql(u8, args[i], "--group")) { i += 1; group = args[i]; }
                else if (mem.eql(u8, args[i], "--pid")) { i += 1; pid = std.fmt.parseInt(u32, args[i], 10) catch 0; }
                else if (mem.eql(u8, args[i], "--dry-run")) dry = true;
            }
        } else if (mem.eql(u8, args[i], "--policy")) { i += 1; policy = args[i]; }
        else if (mem.eql(u8, args[i], "--runtime-state")) { i += 1; run = args[i]; }
        else if (mem.eql(u8, args[i], "--dry-run")) dry = true;
    }

    switch (cmd) {
        .attach => {
            if (group.len == 0 or pid == 0) return;
            const cg = try std.fmt.allocPrint(arena, "/sys/fs/cgroup/alpenglow/{s}", .{group});
            try std.Io.Dir.cwd().createDirPath(io, cg);
            const buf = try std.fmt.allocPrint(arena, "{d}\n", .{pid});
            writeKernelFile(io, cg, "cgroup.procs", buf);
        },
        .apply => {
            const raw = try std.Io.Dir.cwd().readFileAlloc(io, policy, gpa, .limited(1024 * 1024));
            defer gpa.free(raw);
            const parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
            defer parsed.deinit();
            const root = parsed.value;

            const profile = root.object.get("profile").?.string;
            var groups = std.ArrayList(CgPol).empty;

            if (root.object.get("groups")) |arr| {
                try groups.ensureTotalCapacity(gpa, arr.array.items.len);
                for (arr.array.items) |item| {
                    const o = item.object;
                    try groups.append(gpa, .{
                        .path = o.get("path").?.string,
                        .cpu_weight = if (o.get("cpu_weight")) |v| @intCast(v.integer) else null,
                        .io_weight = if (o.get("io_weight")) |v| @intCast(v.integer) else null,
                        .memory_high = if (o.get("memory_high")) |v| try gpa.dupe(u8, v.string) else null,
                        .memory_max = if (o.get("memory_max")) |v| try gpa.dupe(u8, v.string) else null,
                        .pids_max = if (o.get("pids_max")) |v| @intCast(v.integer) else null,
                    });
                }
            }
            defer groups.deinit(gpa);

            var sysctls = std.ArrayList([2][]const u8).empty;
            defer sysctls.deinit(gpa);
            if (root.object.get("sysctl")) |obj| {
                try sysctls.ensureTotalCapacity(gpa, obj.object.count());
                var it = obj.object.iterator();
                while (it.next()) |e| try sysctls.append(gpa, .{ e.key_ptr.*, e.value_ptr.*.string });
            }

            if (!dry) {
                // ponytail: modules loaded via kernel cmdline, skip modprobe spawn
                for (sysctls.items) |s| {
                    var p: [256]u8 = undefined;
                    @memcpy(p[0.."/proc/sys/".len], "/proc/sys/");
                    var idx: usize = "/proc/sys/".len;
                    for (s[0]) |ch| { p[idx] = if (ch == '.') '/' else ch; idx += 1; }
                    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = p[0..idx], .data = s[1] }) catch {};
                }
            }
            try applyCgroups(io, gpa, groups.items, dry);
            try writeEnv(io, run, "ALPENGLOW_KERNEL_POLICY_FILE", policy);
            try writeEnv(io, run, "ALPENGLOW_KERNEL_POLICY_PROFILE", profile);
        },
    }
}

fn applyCgroups(io: std.Io, alloc: mem.Allocator, groups: []CgPol, dry: bool) !void {
    if (dry) return;
    _ = std.Io.Dir.cwd().createDirPath(io, "/sys/fs/cgroup/alpenglow/") catch {};
    for (groups) |g| {
        const dir = try std.fmt.allocPrint(alloc, "/sys/fs/cgroup/{s}", .{g.path});
        defer alloc.free(dir);
        std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        try wU64(io, dir, "cpu.weight", g.cpu_weight);
        try wU64(io, dir, "io.weight", g.io_weight);
        try wStr(io, dir, "memory.high", g.memory_high);
        try wStr(io, dir, "memory.max", g.memory_max);
        try wU64(io, dir, "pids.max", g.pids_max);
    }
}

fn wU64(io: std.Io, dir: []const u8, f: []const u8, v: ?u64) !void {
    if (v) |x| { var b: [32]u8 = undefined; writeKernelFile(io, dir, f, try std.fmt.bufPrint(&b, "{d}\n", .{x})); }
}
fn wStr(io: std.Io, dir: []const u8, f: []const u8, v: ?[]const u8) !void {
    if (v) |s| { writeKernelFile(io, dir, f, s); }
}

fn writeKernelFile(io: std.Io, dir: []const u8, file: []const u8, val: []const u8) void {
    var b: [512]u8 = undefined;
    @memcpy(b[0..dir.len], dir);
    b[dir.len] = '/';
    const rest = b[dir.len + 1 ..];
    @memcpy(rest[0..file.len], file);
    const combined = b[0 .. dir.len + 1 + file.len];
    var buf: [4096]u8 = undefined;
    @memcpy(buf[0..val.len], val);
    if (val.len == 0 or val[val.len - 1] != '\n') { buf[val.len] = '\n'; }
    const data = buf[0..val.len + @intFromBool(val.len == 0 or val[val.len - 1] != '\n')];
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = combined, .data = data }) catch {};
}

fn writeEnv(io: std.Io, path: []const u8, key: []const u8, value: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| _ = std.Io.Dir.cwd().createDirPath(io, parent) catch {};
    var line = std.ArrayList(u8).initCapacity(std.heap.page_allocator, key.len + 1 + value.len + 1) catch return;
    defer line.deinit(std.heap.page_allocator);
    line.appendSliceAssumeCapacity(key);
    line.appendAssumeCapacity('=');
    line.appendSliceAssumeCapacity(value);
    line.appendAssumeCapacity('\n');
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = line.items }) catch {};
}
