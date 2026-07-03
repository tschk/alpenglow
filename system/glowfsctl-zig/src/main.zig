const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

const magic = "GLWFSV01";
const hdr_len = 56;
const ent_len = 92;
const k_dir: u32 = 1;
const k_file: u32 = 2;
const k_sym: u32 = 3;
const f_ro: u64 = 1;
const f_rw: u64 = 2;

const Mode = enum { ro, rw };

const Hdr = extern struct {
    magic: [8]u8,
    version: u32,
    entry_count: u32,
    entries_offset: u64,
    names_offset: u64,
    data_offset: u64,
    image_size: u64,
    flags: u64,
};

const ent_off_inode: usize = 0;
const ent_off_parent: usize = 8;
const ent_off_name_off: usize = 16;
const ent_off_name_len: usize = 24;
const ent_off_kind: usize = 28;
const ent_off_mode: usize = 32;
const ent_off_uid: usize = 36;
const ent_off_gid: usize = 40;
const ent_off_data_off: usize = 44;
const ent_off_size: usize = 52;
const ent_off_digest: usize = 60;

fn readU64(data: []const u8, off: usize) u64 {
    return std.mem.readInt(u64, data[off..][0..8], .little);
}
fn readU32(data: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, data[off..][0..4], .little);
}
fn writeU64(data: []u8, off: usize, v: u64) void {
    std.mem.writeInt(u64, data[off..][0..8], v, .little);
}
fn writeU32(data: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, data[off..][0..4], v, .little);
}

fn MyArrayList(comptime T: type) type {
    if (comptime builtin.zig_version.minor >= 16) {
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
            pub fn appendNTimes(self: *@This(), value: T, n: usize) !void {
                return try self.inner.appendNTimes(self.gpa, value, n);
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
            pub fn appendNTimes(self: *@This(), value: T, n: usize) !void {
                return try self.inner.appendNTimes(value, n);
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

fn joinPath(arena: std.mem.Allocator, a: []const u8, b: []const u8) ![]const u8 {
    if (a.len == 0 or std.mem.eql(u8, a, ".")) return arena.dupe(u8, b);
    const need_sep = a[a.len - 1] != '/';
    const total = a.len + b.len + if (need_sep) @as(usize, 1) else 0;
    const out = try arena.alloc(u8, total);
    @memcpy(out[0..a.len], a);
    var idx = a.len;
    if (need_sep) {
        out[idx] = '/';
        idx += 1;
    }
    @memcpy(out[idx .. idx + b.len], b);
    return out;
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

fn sysGetdents64(fd: i32, buf: []u8) SyscallError!usize {
    const rc = linux.getdents64(fd, buf.ptr, buf.len);
    try checkSyscall(rc);
    return rc;
}

fn writeFile(path: []const u8, data: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, data);
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

fn readFile(gpa: std.mem.Allocator, path: []const u8) SyscallError![]u8 {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .CLOEXEC = true }, 0);
    defer sysClose(fd);
    var stack_buf: [4096]u8 = undefined;
    var result = MyArrayList(u8).init(gpa);
    errdefer result.deinit();
    while (true) {
        const n = try sysRead(fd, &stack_buf);
        if (n == 0) break;
        try result.appendSlice(stack_buf[0..n]);
    }
    return try result.toOwnedSlice();
}

fn writeStdout(msg: []const u8) void {
    _ = linux.write(1, msg.ptr, msg.len);
}

fn writeStderr(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
    writeStderr(msg);
    writeStderr("\n");
    std.process.exit(1);
}

fn digest(data: []const u8) [32]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(data);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

fn hex(d: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(&d, .lower);
}

fn aln8(v: u64) u64 {
    return (v + 7) & ~@as(u64, 7);
}

fn appendU32(buf: *MyArrayList(u8), v: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, .little);
    try buf.appendSlice(&b);
}
fn appendU64(buf: *MyArrayList(u8), v: u64) !void {
    var b: [8]u8 = undefined;
    std.mem.writeInt(u64, &b, v, .little);
    try buf.appendSlice(&b);
}

const FileEntry = struct { path: []const u8, data: []u8, digest: [32]u8 };

fn collectFiles(gpa: std.mem.Allocator, src: []const u8) SyscallError![]FileEntry {
    var result = MyArrayList(FileEntry).init(gpa);
    errdefer {
        for (result.items()) |f| {
            gpa.free(f.path);
            gpa.free(f.data);
        }
        result.deinit();
    }

    var path_buf: [4096]u8 = undefined;
    const src_z = pathToZ(src, &path_buf) orelse return error.NameTooLong;
    const base_fd = try sysOpen(src_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    defer sysClose(base_fd);

    var dents_buf: [8192]u8 align(8) = undefined;
    while (true) {
        const n = try sysGetdents64(base_fd, &dents_buf);
        if (n == 0) break;
        var offset: usize = 0;
        while (offset < n) {
            const entry = @as(*linux.dirent64, @ptrCast(@alignCast(&dents_buf[offset])));
            const name_ptr: [*:0]u8 = @ptrCast(&entry.name);
            const name = std.mem.span(name_ptr);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                if (entry.type == linux.DT.DIR or entry.type == linux.DT.LNK) {
                    // recurse into directories
                    const subpath = try joinPath(gpa, src, name);
                    const subfiles = try collectFiles(gpa, subpath);
                    for (subfiles) |f| {
                        try result.append(f);
                    }
                    gpa.free(subfiles);
                    gpa.free(subpath);
                } else if (entry.type == linux.DT.REG) {
                    const full_path = try joinPath(gpa, src, name);
                    const data = try readFile(gpa, full_path);
                    try result.append(.{ .path = full_path, .data = data, .digest = digest(data) });
                }
            }
            offset += entry.reclen;
        }
    }

    return try result.toOwnedSlice();
}

fn buildImage(gpa: std.mem.Allocator, src: []const u8, out: []const u8, mode: Mode) !void {
    const files = try collectFiles(gpa, src);
    defer {
        for (files) |f| {
            gpa.free(f.path);
            gpa.free(f.data);
        }
        gpa.free(files);
    }

    const nentries: u32 = @intCast(files.len + 1);

    const ent_off: u64 = hdr_len;
    var ns: u64 = 0;
    for (files) |f| ns += std.fs.path.basename(f.path).len;
    const nam_off = ent_off + @as(u64, nentries) * ent_len;
    const dat_off = aln8(nam_off + ns);

    var buf = MyArrayList(u8).init(gpa);
    defer buf.deinit();

    try buf.appendSlice(magic);
    try appendU32(&buf, 1);
    try appendU32(&buf, nentries);
    try appendU64(&buf, ent_off);
    try appendU64(&buf, nam_off);
    try appendU64(&buf, dat_off);
    try appendU64(&buf, 0); // placeholder
    try appendU64(&buf, if (mode == .ro) f_ro else f_rw);

    try appendU64(&buf, 1);
    try appendU64(&buf, 1);
    try appendU64(&buf, 0);
    try appendU32(&buf, 0);
    try appendU32(&buf, k_dir);
    try appendU32(&buf, 0o755);
    try appendU32(&buf, 0);
    try appendU32(&buf, 0);
    try appendU64(&buf, 0);
    try appendU64(&buf, 0);
    try buf.appendNTimes(@as(u8, 0), 32);

    var cur = dat_off;
    var names = MyArrayList(u8).init(gpa);
    defer names.deinit();

    for (files) |f| {
        const base = std.fs.path.basename(f.path);
        const noff = names.items().len;
        try names.appendSlice(base);
        try appendU64(&buf, nentries);
        try appendU64(&buf, 1);
        try appendU64(&buf, @intCast(noff));
        try appendU32(&buf, @intCast(base.len));
        try appendU32(&buf, k_file);
        try appendU32(&buf, 0o644);
        try appendU32(&buf, 0);
        try appendU32(&buf, 0);
        try appendU64(&buf, cur);
        try appendU64(&buf, @intCast(f.data.len));
        try buf.appendSlice(&f.digest);
        cur = aln8(cur + f.data.len);
    }

    try buf.appendSlice(names.items());
    while (buf.items().len < dat_off) try buf.appendNTimes(@as(u8, 0), 1);
    for (files) |f| {
        try buf.appendSlice(f.data);
        while (buf.items().len < aln8(@intCast(buf.items().len))) try buf.appendNTimes(@as(u8, 0), 1);
    }
    std.mem.writeInt(u64, buf.items()[40..48], @intCast(buf.items().len), .little);

    try writeFile(out, buf.items());

    var sb: [128]u8 = undefined;
    const s = try std.fmt.bufPrint(&sb, "glowfs image entries={d} size={d}\n", .{ nentries, buf.items().len });
    writeStdout(s);
}

fn inspectImage(gpa: std.mem.Allocator, path: []const u8) !void {
    const data = try readFile(gpa, path);
    defer gpa.free(data);
    if (data.len < hdr_len) return fatal("truncated image", .{});
    const h = @as(*align(1) const Hdr, @ptrCast(data[0..hdr_len]));
    if (!std.mem.eql(u8, &h.magic, magic)) return fatal("bad magic", .{});
    if (h.version != 1) return fatal("bad version {d}", .{h.version});

    var sb: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&sb, "glowfs entries={d} size={d} flags={d}\n", .{ h.entry_count, h.image_size, h.flags });
    writeStdout(s);

    for (0..h.entry_count) |i| {
        const off = h.entries_offset + @as(u64, i) * ent_len;
        if (off + ent_len > data.len) return fatal("corrupt image: entry out of bounds", .{});
        const e = data[@as(usize, @intCast(off))..][0..ent_len];
        const name_len = readU32(e, ent_off_name_len);
        const name = if (name_len > 0) blk: {
            const name_off = readU64(e, ent_off_name_off);
            if (h.names_offset + name_off + name_len > data.len) return fatal("corrupt image: name out of bounds", .{});
            break :blk data[@as(usize, @intCast(h.names_offset + name_off))..][0..@as(usize, @intCast(name_len))];
        } else "(root)";
        const kind = readU32(e, ent_off_kind);
        const kind_str = if (kind == k_dir) "dir" else if (kind == k_file) "file" else "?";
        const size = readU64(e, ent_off_size);
        const hs = try std.fmt.bufPrint(&sb, "  {s} ino={d} parent={d} kind={s} size={d} digest={s}\n", .{
            name,                                                                               readU64(e, ent_off_inode), readU64(e, ent_off_parent), kind_str, size,
            if (kind != k_dir) @as(*const [64]u8, &hex(e[ent_off_digest..ent_len].*)) else "-",
        });
        writeStdout(hs);
    }
}

fn readFileFromImage(gpa: std.mem.Allocator, image: []const u8, path: []const u8) !void {
    const data = try readFile(gpa, image);
    defer gpa.free(data);
    if (data.len < hdr_len) return fatal("truncated image", .{});
    const h = @as(*align(1) const Hdr, @ptrCast(data[0..hdr_len]));
    if (!std.mem.eql(u8, &h.magic, magic)) return fatal("bad magic", .{});

    const base = std.fs.path.basename(path);
    for (0..h.entry_count) |i| {
        const off = h.entries_offset + @as(u64, i) * ent_len;
        if (off + ent_len > data.len) return fatal("corrupt image: entry out of bounds", .{});
        const e = data[@as(usize, @intCast(off))..][0..ent_len];
        const name_len = readU32(e, ent_off_name_len);
        if (name_len == 0) continue;
        const name_off = readU64(e, ent_off_name_off);
        if (h.names_offset + name_off + name_len > data.len) return fatal("corrupt image: name out of bounds", .{});
        const name = data[@as(usize, @intCast(h.names_offset + name_off))..][0..@as(usize, @intCast(name_len))];
        if (std.mem.eql(u8, name, base)) {
            const data_off = readU64(e, ent_off_data_off);
            const size = readU64(e, ent_off_size);
            if (data_off + size > data.len) return fatal("corrupt image: data out of bounds", .{});
            _ = linux.write(1, data[@as(usize, @intCast(data_off))..].ptr, @intCast(size));
            return;
        }
    }
    return fatal("file not found: {s}", .{path});
}

fn writeFileToImage(gpa: std.mem.Allocator, image: []const u8, path: []const u8, value: []const u8) !void {
    var data = try readFile(gpa, image);
    defer gpa.free(data);
    if (data.len < hdr_len) return fatal("truncated image", .{});
    const h = @as(*align(1) const Hdr, @ptrCast(data[0..hdr_len]));
    if (!std.mem.eql(u8, &h.magic, magic)) return fatal("bad magic", .{});
    if (h.flags & f_rw == 0) return fatal("image is read-only", .{});

    const base = std.fs.path.basename(path);
    for (0..h.entry_count) |i| {
        const off = h.entries_offset + @as(u64, i) * ent_len;
        if (off + ent_len > data.len) return fatal("corrupt image: entry out of bounds", .{});
        const e = data[@as(usize, @intCast(off))..][0..ent_len];
        const name_len = readU32(e, ent_off_name_len);
        if (name_len == 0) continue;
        const name_off = readU64(e, ent_off_name_off);
        if (h.names_offset + name_off + name_len > data.len) return fatal("corrupt image: name out of bounds", .{});
        const name = data[@as(usize, @intCast(h.names_offset + name_off))..][0..@as(usize, @intCast(name_len))];
        if (!std.mem.eql(u8, name, base)) continue;
        const e_data_off = readU64(e, ent_off_data_off);
        const e_size = readU64(e, ent_off_size);
        if (e_data_off + e_size > data.len) return fatal("corrupt image: data out of bounds", .{});

        const eo = @as(usize, @intCast(off));
        if (value.len <= e_size) {
            @memcpy(data[@as(usize, @intCast(e_data_off))..][0..value.len], value);
            if (value.len < e_size)
                @memset(data[@as(usize, @intCast(e_data_off)) + value.len ..][0 .. @as(usize, @intCast(e_size)) - value.len], 0);
        } else if (aln8(e_data_off + e_size) == aln8(h.image_size)) {
            const needed = @as(usize, @intCast(e_data_off)) + value.len;
            data = try gpa.realloc(data, needed);
            @memcpy(data[@as(usize, @intCast(e_data_off))..][0..value.len], value);
            writeU64(data, eo + ent_off_size, @intCast(value.len));
            @memcpy(data[eo + ent_off_digest .. eo + ent_len], &digest(value));
            std.mem.writeInt(u64, data[40..48], @intCast(needed), .little);
        } else {
            const new_off = aln8(h.image_size);
            const needed = @as(usize, @intCast(new_off)) + value.len;
            data = try gpa.realloc(data, needed);
            @memcpy(data[@as(usize, @intCast(new_off))..][0..value.len], value);
            writeU64(data, eo + ent_off_data_off, new_off);
            writeU64(data, eo + ent_off_size, @intCast(value.len));
            @memcpy(data[eo + ent_off_digest .. eo + ent_len], &digest(value));
            std.mem.writeInt(u64, data[40..48], @intCast(needed), .little);
        }
        try writeFile(image, data);
        return;
    }
    return fatal("file not found: {s}", .{path});
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    const args = try readCmdline(gpa);

    if (args.len < 2) return fatal("usage: glowfsctl {{mkfs|inspect|read|write}} ...", .{});
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "mkfs")) {
        if (args.len < 4) return fatal("usage: glowfsctl mkfs <src> <out> [--rw]", .{});
        const mode: Mode = if (args.len > 4 and std.mem.eql(u8, args[4], "--rw")) .rw else .ro;
        try buildImage(gpa, args[2], args[3], mode);
    } else if (std.mem.eql(u8, cmd, "inspect")) {
        if (args.len < 3) return fatal("usage: glowfsctl inspect <image>", .{});
        try inspectImage(gpa, args[2]);
    } else if (std.mem.eql(u8, cmd, "read")) {
        if (args.len < 4) return fatal("usage: glowfsctl read <image> <path>", .{});
        try readFileFromImage(gpa, args[2], args[3]);
    } else if (std.mem.eql(u8, cmd, "write")) {
        if (args.len < 5) return fatal("usage: glowfsctl write <image> <path> <value>", .{});
        try writeFileToImage(gpa, args[2], args[3], args[4]);
    } else {
        return fatal("unknown command: {s}", .{cmd});
    }
}
