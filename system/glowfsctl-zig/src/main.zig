const std = @import("std");

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

const Ent = extern struct {
    inode: u64,
    parent: u64,
    name_off: u64,
    name_len: u32,
    kind: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    data_off: u64,
    size: u64,
    digest: [32]u8,
};

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

fn aln8(v: u64) u64 { return (v + 7) & ~@as(u64, 7); }

fn fatal(io: std.Io, comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
    std.Io.File.stderr().writeStreamingAll(io, msg) catch {};
    std.Io.File.stderr().writeStreamingAll(io, "\n") catch {};
    std.process.exit(1);
}

const FileEntry = struct { path: []const u8, data: []u8, digest: [32]u8 };

fn buildImage(io: std.Io, gpa: std.mem.Allocator, src: []const u8, out: []const u8, mode: Mode) !void {
    const dir = try std.Io.Dir.cwd().openDir(io, src, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var files = try std.ArrayList(FileEntry).initCapacity(gpa, 64);
    defer files.deinit(gpa);
    var nentries: u32 = 1;

    while (try walker.next(io)) |w| {
        if (w.kind != .file) continue;
        nentries += 1;
        const data = try std.Io.Dir.cwd().readFileAlloc(io, w.path, gpa, .unlimited);
        errdefer gpa.free(data);
        try files.append(gpa, .{ .path = w.path, .data = data, .digest = digest(data) });
    }

    const ent_off: u64 = hdr_len;
    var ns: u64 = 0;
    for (files.items) |f| ns += std.fs.path.basename(f.path).len;
    const nam_off = ent_off + @as(u64, nentries) * ent_len;
    const dat_off = aln8(nam_off + ns);

    var buf = try std.ArrayList(u8).initCapacity(gpa, 4096);
    defer buf.deinit(gpa);

    try buf.appendSlice(gpa, magic);
    try appendU32(&buf, gpa, 1);
    try appendU32(&buf, gpa, nentries);
    try appendU64(&buf, gpa, ent_off);
    try appendU64(&buf, gpa, nam_off);
    try appendU64(&buf, gpa, dat_off);
    try appendU64(&buf, gpa, 0); // placeholder
    try appendU64(&buf, gpa, if (mode == .ro) f_ro else f_rw);

    try appendU64(&buf, gpa, 1); try appendU64(&buf, gpa, 1);
    try appendU64(&buf, gpa, 0); try appendU32(&buf, gpa, 0);
    try appendU32(&buf, gpa, k_dir); try appendU32(&buf, gpa, 0o755);
    try appendU32(&buf, gpa, 0); try appendU32(&buf, gpa, 0);
    try appendU64(&buf, gpa, 0); try appendU64(&buf, gpa, 0);
    try buf.appendNTimes(gpa, @as(u8, 0), 32);

    var cur = dat_off;
    var names = try std.ArrayList(u8).initCapacity(gpa, 256);
    defer names.deinit(gpa);

    for (files.items) |f| {
        const base = std.fs.path.basename(f.path);
        const noff = names.items.len;
        try names.appendSlice(gpa, base);
        try appendU64(&buf, gpa, nentries); try appendU64(&buf, gpa, 1);
        try appendU64(&buf, gpa, @intCast(noff)); try appendU32(&buf, gpa, @intCast(base.len));
        try appendU32(&buf, gpa, k_file); try appendU32(&buf, gpa, 0o644);
        try appendU32(&buf, gpa, 0); try appendU32(&buf, gpa, 0);
        try appendU64(&buf, gpa, cur); try appendU64(&buf, gpa, @intCast(f.data.len));
        try buf.appendSlice(gpa, &f.digest);
        cur = aln8(cur + f.data.len);
    }

    try buf.appendSlice(gpa, names.items);
    while (buf.items.len < dat_off) try buf.append(gpa, 0);
    for (files.items) |f| {
        try buf.appendSlice(gpa, f.data);
        while (buf.items.len < aln8(@intCast(buf.items.len))) try buf.append(gpa, 0);
    }
    std.mem.writeInt(u64, buf.items[40..48], @intCast(buf.items.len), .little);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out, .data = buf.items });

    var sb: [128]u8 = undefined;
    const s = try std.fmt.bufPrint(&sb, "glowfs image entries={d} size={d}\n", .{ nentries, buf.items.len });
    try std.Io.File.stdout().writeStreamingAll(io, s);
}

fn appendU32(buf: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u32) !void {
    var b: [4]u8 = undefined; std.mem.writeInt(u32, &b, v, .little); try buf.appendSlice(gpa, &b);
}
fn appendU64(buf: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u64) !void {
    var b: [8]u8 = undefined; std.mem.writeInt(u64, &b, v, .little); try buf.appendSlice(gpa, &b);
}

fn inspectImage(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(data);
    if (data.len < hdr_len) return fatal(io, "truncated image", .{});
    const h = @as(*align(1) const Hdr, @ptrCast(data[0..hdr_len]));
    if (!std.mem.eql(u8, &h.magic, magic)) return fatal(io, "bad magic", .{});
    if (h.version != 1) return fatal(io, "bad version {d}", .{h.version});

    var sb: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&sb, "glowfs entries={d} size={d} flags={d}\n", .{ h.entry_count, h.image_size, h.flags });
    try std.Io.File.stdout().writeStreamingAll(io, s);

    for (0..h.entry_count) |i| {
        const off = h.entries_offset + @as(u64, i) * ent_len;
        const e = @as(*align(1) const Ent, @ptrCast(data[@as(usize, @intCast(off))..][0..ent_len]));
        const name = if (e.name_len > 0)
            data[@as(usize, @intCast(h.names_offset + e.name_off))..][0..@as(usize, @intCast(e.name_len))]
        else
            "(root)";
        const kind = if (e.kind == k_dir) "dir" else if (e.kind == k_file) "file" else "?";
        const hs = try std.fmt.bufPrint(&sb, "  {s} ino={d} parent={d} kind={s} size={d} digest={s}\n", .{
            name, e.inode, e.parent, kind, e.size,
            if (e.kind != k_dir) @as(*const [64]u8, &hex(e.digest)) else "-",
        });
        try std.Io.File.stdout().writeStreamingAll(io, hs);
    }
}

fn readFile(io: std.Io, gpa: std.mem.Allocator, image: []const u8, path: []const u8) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, image, gpa, .unlimited);
    defer gpa.free(data);
    if (data.len < hdr_len) return fatal(io, "truncated image", .{});
    const h = @as(*align(1) const Hdr, @ptrCast(data[0..hdr_len]));
    if (!std.mem.eql(u8, &h.magic, magic)) return fatal(io, "bad magic", .{});

    const base = std.fs.path.basename(path);
    for (0..h.entry_count) |i| {
        const off = h.entries_offset + @as(u64, i) * ent_len;
        const e = @as(*align(1) const Ent, @ptrCast(data[@as(usize, @intCast(off))..][0..ent_len]));
        if (e.name_len == 0) continue;
        const name = data[@as(usize, @intCast(h.names_offset + e.name_off))..][0..@as(usize, @intCast(e.name_len))];
        if (std.mem.eql(u8, name, base)) {
            try std.Io.File.stdout().writeStreamingAll(io, data[@as(usize, @intCast(e.data_off))..][0..@as(usize, @intCast(e.size))]);
            return;
        }
    }
    return fatal(io, "file not found: {s}", .{path});
}

fn writeFile(io: std.Io, gpa: std.mem.Allocator, image: []const u8, path: []const u8, value: []const u8) !void {
    var data = try std.Io.Dir.cwd().readFileAlloc(io, image, gpa, .unlimited);
    defer gpa.free(data);
    if (data.len < hdr_len) return fatal(io, "truncated image", .{});
    const h = @as(*align(1) const Hdr, @ptrCast(data[0..hdr_len]));
    if (!std.mem.eql(u8, &h.magic, magic)) return fatal(io, "bad magic", .{});
    if (h.flags & f_rw == 0) return fatal(io, "image is read-only", .{});

    const base = std.fs.path.basename(path);
    for (0..h.entry_count) |i| {
        const off = h.entries_offset + @as(u64, i) * ent_len;
        const e = @as(*align(1) const Ent, @ptrCast(data[@as(usize, @intCast(off))..][0..ent_len]));
        if (e.name_len == 0) continue;
        const name = data[@as(usize, @intCast(h.names_offset + e.name_off))..][0..@as(usize, @intCast(e.name_len))];
        if (!std.mem.eql(u8, name, base)) continue;

        const eo = @as(usize, @intCast(off));
        if (value.len <= e.size) {
            @memcpy(data[@as(usize, @intCast(e.data_off))..][0..value.len], value);
            if (value.len < e.size)
                @memset(data[@as(usize, @intCast(e.data_off)) + value.len ..][0..@as(usize, @intCast(e.size)) - value.len], 0);
        } else if (aln8(e.data_off + e.size) == aln8(h.image_size)) {
            const needed = @as(usize, @intCast(e.data_off)) + value.len;
            data = try gpa.realloc(data, needed);
            @memcpy(data[@as(usize, @intCast(e.data_off))..][0..value.len], value);
            std.mem.writeInt(u64, data[eo + 52 ..][0..8], @intCast(value.len), .little);
            @memcpy(data[eo + 60 .. eo + 92], &digest(value));
            std.mem.writeInt(u64, data[40..48], @intCast(needed), .little);
        } else {
            const new_off = aln8(h.image_size);
            const needed = @as(usize, @intCast(new_off)) + value.len;
            data = try gpa.realloc(data, needed);
            @memcpy(data[@as(usize, @intCast(new_off))..][0..value.len], value);
            std.mem.writeInt(u64, data[eo + 44 ..][0..8], new_off, .little);
            std.mem.writeInt(u64, data[eo + 52 ..][0..8], @intCast(value.len), .little);
            @memcpy(data[eo + 60 .. eo + 92], &digest(value));
            std.mem.writeInt(u64, data[40..48], @intCast(needed), .little);
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = image, .data = data });
        return;
    }
    return fatal(io, "file not found: {s}", .{path});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return fatal(io, "usage: glowfsctl mkfs [--mutable] <src> <out> | inspect <img> | read <img> <path> | write <img> <path> <val>", .{});

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "mkfs")) {
        var mode = Mode.ro;
        var i: usize = 2;
        if (i < args.len and std.mem.eql(u8, args[i], "--mutable")) { mode = .rw; i += 1; }
        if (i + 1 >= args.len) return fatal(io, "usage: glowfsctl mkfs [--mutable] <src> <out>", .{});
        try buildImage(io, gpa, args[i], args[i + 1], mode);
    } else if (std.mem.eql(u8, cmd, "inspect")) {
        if (args.len < 3) return fatal(io, "usage: glowfsctl inspect <img>", .{});
        try inspectImage(io, gpa, args[2]);
    } else if (std.mem.eql(u8, cmd, "read")) {
        if (args.len < 4) return fatal(io, "usage: glowfsctl read <img> <path>", .{});
        try readFile(io, gpa, args[2], args[3]);
    } else if (std.mem.eql(u8, cmd, "write")) {
        if (args.len < 5) return fatal(io, "usage: glowfsctl write <img> <path> <val>", .{});
        try writeFile(io, gpa, args[2], args[3], args[4]);
    } else return fatal(io, "unknown command: {s}", .{cmd});
}
