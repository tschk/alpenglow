const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const mem = std.mem;

fn MyArrayList(comptime T: type) type {
    if (comptime builtin.zig_version.minor >= 15) {
        return struct {
            const Inner = std.ArrayList(T);
            inner: Inner,
            gpa: std.mem.Allocator,

            pub fn init(gpa: std.mem.Allocator) @This() {
                return .{ .inner = Inner.empty, .gpa = gpa };
            }
            pub fn deinit(self: *@This()) void {
                self.inner.deinit(self.gpa);
            }
            pub fn append(self: *@This(), item: T) !void {
                return try self.inner.append(self.gpa, item);
            }
            pub fn appendSlice(self: *@This(), new_items: []const T) !void {
                return try self.inner.appendSlice(self.gpa, new_items);
            }
            pub fn items(self: *const @This()) []T {
                return self.inner.items;
            }
            pub fn toOwnedSlice(self: *@This()) ![]T {
                return try self.inner.toOwnedSlice(self.gpa);
            }
        };
    } else {
        return struct {
            const Inner = std.ArrayList(T);
            inner: Inner,

            pub fn init(gpa: std.mem.Allocator) @This() {
                return .{ .inner = Inner.init(gpa) };
            }
            pub fn deinit(self: *@This()) void {
                self.inner.deinit();
            }
            pub fn append(self: *@This(), item: T) !void {
                return try self.inner.append(item);
            }
            pub fn appendSlice(self: *@This(), new_items: []const T) !void {
                return try self.inner.appendSlice(new_items);
            }
            pub fn items(self: *const @This()) []T {
                return self.inner.items;
            }
            pub fn toOwnedSlice(self: *@This()) ![]T {
                return try self.inner.toOwnedSlice();
            }
        };
    }
}

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

const SyscallError = error{
    FileNotFound,
    AccessDenied,
    PathAlreadyExists,
    NotDir,
    IsDir,
    InvalidArgument,
    OutOfMemory,
    FileTooBig,
    InputOutput,
    DeviceBusy,
    WouldBlock,
    Interrupted,
    NameTooLong,
    NotEmpty,
    Unexpected,
};

fn getErrno(rc: usize) linux.E {
    const signed: isize = @bitCast(rc);
    if (signed > -4096 and signed < 0) {
        return @enumFromInt(-signed);
    }
    return .SUCCESS;
}

fn checkSyscall(rc: usize) SyscallError!void {
    switch (getErrno(rc)) {
        .SUCCESS => return,
        .NOENT => return error.FileNotFound,
        .ACCES => return error.AccessDenied,
        .EXIST => return error.PathAlreadyExists,
        .NOTDIR => return error.NotDir,
        .ISDIR => return error.IsDir,
        .INVAL => return error.InvalidArgument,
        .NOMEM => return error.OutOfMemory,
        .FBIG => return error.FileTooBig,
        .IO => return error.InputOutput,
        .BUSY => return error.DeviceBusy,
        .AGAIN => return error.WouldBlock,
        .INTR => return error.Interrupted,
        .NAMETOOLONG => return error.NameTooLong,
        .NOTEMPTY => return error.NotEmpty,
        else => return error.Unexpected,
    }
}

fn pathToZ(path: []const u8, buf: []u8) ?[:0]const u8 {
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

fn sysOpen(path: [*:0]const u8, flags: linux.O, mode: linux.mode_t) SyscallError!i32 {
    const rc = linux.open(path, flags, mode);
    try checkSyscall(rc);
    return @intCast(rc);
}

fn sysOpenat(dirfd: i32, path: [*:0]const u8, flags: linux.O, mode: linux.mode_t) SyscallError!i32 {
    const rc = linux.openat(dirfd, path, flags, mode);
    try checkSyscall(rc);
    return @intCast(rc);
}

fn sysRead(fd: i32, buf: []u8) SyscallError!usize {
    const rc = linux.read(fd, buf.ptr, buf.len);
    try checkSyscall(rc);
    return rc;
}

fn sysWrite(fd: i32, data: []const u8) SyscallError!void {
    var written: usize = 0;
    while (written < data.len) {
        const rc = linux.write(fd, data.ptr + written, data.len - written);
        try checkSyscall(rc);
        written += rc;
    }
}

fn sysClose(fd: i32) void {
    _ = linux.close(fd);
}

fn sysMkdir(path: [*:0]const u8, mode: linux.mode_t) SyscallError!void {
    const rc = linux.mkdir(path, mode);
    if (getErrno(rc) == .EXIST) return;
    try checkSyscall(rc);
}

fn makeDir(path: []const u8) SyscallError!void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    try sysMkdir(path_z, 0o755);
}

fn makePathRecursive(path: []const u8) !void {
    if (path.len == 0 or std.mem.eql(u8, path, "/")) return;
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') {
            makeDir(path[0..i]) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
    }
    makeDir(path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn writeFile(path: []const u8, data: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, data);
}

fn writeFileNoTrunc(path: []const u8, data: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .CLOEXEC = true }, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, data);
}

fn readFileLimited(gpa: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer sysClose(fd);
    var out = MyArrayList(u8).init(gpa);
    errdefer out.deinit();
    while (true) {
        var chunk: [4096]u8 = undefined;
        const n = try sysRead(fd, &chunk);
        if (n == 0) break;
        if (out.items().len + n > max) return error.FileTooBig;
        try out.appendSlice(chunk[0..n]);
    }
    return try out.toOwnedSlice();
}

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

fn writeStderr(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

pub fn main() !void {
    mainInner() catch |err| {
        writeStderr("alpenglow-kernelctl: ");
        writeStderr(@errorName(err));
        writeStderr("\n");
        std.process.exit(1);
    };
}

fn mainInner() !void {
    const allocator = std.heap.page_allocator;
    const args = try readCmdline(allocator);

    var i: usize = 1;
    var policy: []const u8 = DFL_POL;
    var run: []const u8 = DFL_RUN;
    var dry = false;
    var cmd: enum { apply, attach } = .apply;
    var group: []const u8 = "";
    var pid: u32 = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.eql(u8, arg, "attach")) {
            cmd = .attach;
            while (i + 1 < args.len) {
                i += 1;
                const inner = args[i];
                if (mem.eql(u8, inner, "--group")) {
                    i += 1;
                    group = args[i];
                } else if (mem.eql(u8, inner, "--pid")) {
                    i += 1;
                    pid = std.fmt.parseInt(u32, args[i], 10) catch 0;
                } else if (mem.eql(u8, inner, "--dry-run")) {
                    dry = true;
                }
            }
        } else if (mem.eql(u8, arg, "--policy")) {
            i += 1;
            policy = args[i];
        } else if (mem.eql(u8, arg, "--runtime-state")) {
            i += 1;
            run = args[i];
        } else if (mem.eql(u8, arg, "--dry-run")) {
            dry = true;
        }
    }

    switch (cmd) {
        .attach => {
            if (group.len == 0 or pid == 0) return;
            const cg = try std.fmt.allocPrint(allocator, "/sys/fs/cgroup/alpenglow/{s}", .{group});
            makePathRecursive(cg) catch {};
            const buf = try std.fmt.allocPrint(allocator, "{d}\n", .{pid});
            writeKernelFile(cg, "cgroup.procs", buf);
        },
        .apply => {
            const raw = try readFileLimited(allocator, policy, 1024 * 1024);
            defer allocator.free(raw);
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
            defer parsed.deinit();
            const root = parsed.value;

            const profile = root.object.get("profile").?.string;
            var groups = MyArrayList(CgPol).init(allocator);

            if (root.object.get("groups")) |arr| {
                for (arr.array.items) |item| {
                    const o = item.object;
                    try groups.append(.{
                        .path = o.get("path").?.string,
                        .cpu_weight = if (o.get("cpu_weight")) |v| @intCast(v.integer) else null,
                        .io_weight = if (o.get("io_weight")) |v| @intCast(v.integer) else null,
                        .memory_high = if (o.get("memory_high")) |v| try allocator.dupe(u8, v.string) else null,
                        .memory_max = if (o.get("memory_max")) |v| try allocator.dupe(u8, v.string) else null,
                        .pids_max = if (o.get("pids_max")) |v| @intCast(v.integer) else null,
                    });
                }
            }
            defer groups.deinit();

            var sysctls = MyArrayList([2][]const u8).init(allocator);
            defer sysctls.deinit();
            if (root.object.get("sysctl")) |obj| {
                var it = obj.object.iterator();
                while (it.next()) |e| try sysctls.append(.{ e.key_ptr.*, e.value_ptr.*.string });
            }

            if (!dry) {
                // ponytail: modules loaded via kernel cmdline, skip modprobe spawn
                for (sysctls.items()) |s| {
                    var p: [256]u8 = undefined;
                    @memcpy(p[0.."/proc/sys/".len], "/proc/sys/");
                    var idx: usize = "/proc/sys/".len;
                    for (s[0]) |ch| {
                        p[idx] = if (ch == '.') '/' else ch;
                        idx += 1;
                    }
                    writeFileNoTrunc(p[0..idx], s[1]) catch {};
                }
            }
            try applyCgroups(allocator, groups.items(), dry);
            try writeEnv(run, "ALPENGLOW_KERNEL_POLICY_FILE", policy);
            try writeEnv(run, "ALPENGLOW_KERNEL_POLICY_PROFILE", profile);
        },
    }
}

fn applyCgroups(alloc: mem.Allocator, groups: []CgPol, dry: bool) !void {
    if (dry) return;
    makeDir("/sys/fs/cgroup/alpenglow/") catch {};
    for (groups) |g| {
        const dir = try std.fmt.allocPrint(alloc, "/sys/fs/cgroup/{s}", .{g.path});
        defer alloc.free(dir);
        makeDir(dir) catch {};
        try wU64(dir, "cpu.weight", g.cpu_weight);
        try wU64(dir, "io.weight", g.io_weight);
        try wStr(dir, "memory.high", g.memory_high);
        try wStr(dir, "memory.max", g.memory_max);
        try wU64(dir, "pids.max", g.pids_max);
    }
}

fn wU64(dir: []const u8, f: []const u8, v: ?u64) !void {
    if (v) |x| {
        var b: [32]u8 = undefined;
        writeKernelFile(dir, f, try std.fmt.bufPrint(&b, "{d}\n", .{x}));
    }
}
fn wStr(dir: []const u8, f: []const u8, v: ?[]const u8) !void {
    if (v) |s| {
        writeKernelFile(dir, f, s);
    }
}

fn writeKernelFile(dir: []const u8, file: []const u8, val: []const u8) void {
    const path_len = dir.len + 1 + file.len;
    // ponytail: max path from /sys/fs/cgroup/ + group path + filename
    var b: [4096]u8 = undefined;
    if (path_len + 1 > b.len) return;
    @memcpy(b[0..dir.len], dir);
    b[dir.len] = '/';
    @memcpy(b[dir.len + 1 ..][0..file.len], file);
    const combined = b[0..path_len];
    var buf: [4096]u8 = undefined;
    @memcpy(buf[0..val.len], val);
    if (val.len == 0 or val[val.len - 1] != '\n') {
        buf[val.len] = '\n';
    }
    const data = buf[0 .. val.len + @intFromBool(val.len == 0 or val[val.len - 1] != '\n')];
    writeFileNoTrunc(combined, data) catch {};
}

fn writeEnv(path: []const u8, key: []const u8, value: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| makePathRecursive(parent) catch {};
    const line = try std.fmt.allocPrint(std.heap.page_allocator, "{s}={s}\n", .{ key, value });
    defer std.heap.page_allocator.free(line);
    try writeFile(path, line);
}
