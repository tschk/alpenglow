const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

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

const DEFAULT_SYS_CLASS_NET = "/sys/class/net";
const DEFAULT_STATE_JSON = "/run/alpenglow/netd/interfaces.json";
const DEFAULT_RUNTIME_ENV = "/run/alpenglow/netd/runtime-state.env";

extern "c" var environ: [*:null]?[*:0]u8;

const Interface = struct {
    name: []const u8,
    index: ?u32 = null,
    kind: []const u8 = "ethernet",
    mac_address: ?[]const u8 = null,
    operstate: []const u8 = "down",
    mtu: ?u32 = null,
    carrier: ?bool = null,
    speed_mbps: ?u32 = null,
    rx_bytes: ?u64 = null,
    tx_bytes: ?u64 = null,
    flags_hex: ?[]const u8 = null,
};

const Snapshot = struct {
    generated_unix_ms: u64,
    interfaces: []const Interface,
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

fn getenv(key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (environ[i]) |entry| : (i += 1) {
        const e = std.mem.span(entry);
        if (std.mem.startsWith(u8, e, key) and e.len > key.len and e[key.len] == '=') {
            return e[key.len + 1 ..];
        }
    }
    return null;
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

fn sysGetdents64(fd: i32, buf: []u8) SyscallError!usize {
    const rc = linux.getdents64(fd, buf.ptr, buf.len);
    try checkSyscall(rc);
    return rc;
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

fn readTrimmed(gpa: std.mem.Allocator, dir_fd: i32, sub_path: []const u8) ?[]const u8 {
    var path_buf: [4096]u8 = undefined;
    const sub_path_z = pathToZ(sub_path, &path_buf) orelse return null;
    const fd = sysOpenat(dir_fd, sub_path_z, .{ .CLOEXEC = true }, 0) catch return null;
    defer sysClose(fd);
    var buf: [4096]u8 = undefined;
    const n = sysRead(fd, &buf) catch return null;
    const trimmed = std.mem.trim(u8, buf[0..n], " \t\r\n");
    if (trimmed.len == 0) return null;
    return gpa.dupe(u8, trimmed) catch null;
}

fn parseU32(value: []const u8) ?u32 {
    return std.fmt.parseInt(u32, value, 10) catch null;
}

fn parseU64(value: []const u8) ?u64 {
    return std.fmt.parseInt(u64, value, 10) catch null;
}

fn parseKind(kind_str: ?[]const u8) []const u8 {
    const value = kind_str orelse return "ethernet";
    const n = std.fmt.parseInt(i32, value, 10) catch return "ethernet";
    return switch (n) {
        772 => "loopback",
        else => "ethernet",
    };
}

fn parseOperstate(value: ?[]const u8) []const u8 {
    const v = value orelse return "down";
    return if (std.mem.eql(u8, v, "up")) "up" else "down";
}

fn parseCarrier(value: ?[]const u8) ?bool {
    const v = value orelse return null;
    return switch (v[0]) {
        '0' => false,
        '1' => true,
        else => null,
    };
}

fn readInterface(gpa: std.mem.Allocator, base_fd: i32, name: []const u8) !Interface {
    var name_buf: [4096]u8 = undefined;
    const name_z = pathToZ(name, &name_buf) orelse return error.NameTooLong;
    const iface_fd = try sysOpenat(base_fd, name_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    defer sysClose(iface_fd);

    const index_str = readTrimmed(gpa, iface_fd, "ifindex");
    const kind_str = readTrimmed(gpa, iface_fd, "type");
    const address = readTrimmed(gpa, iface_fd, "address");
    const operstate_str = readTrimmed(gpa, iface_fd, "operstate");
    const mtu_str = readTrimmed(gpa, iface_fd, "mtu");
    const carrier_str = readTrimmed(gpa, iface_fd, "carrier");
    const speed_str = readTrimmed(gpa, iface_fd, "speed");
    const rx_str = readTrimmed(gpa, iface_fd, "statistics/rx_bytes");
    const tx_str = readTrimmed(gpa, iface_fd, "statistics/tx_bytes");
    const flags_str = readTrimmed(gpa, iface_fd, "flags");

    return Interface{
        .name = try gpa.dupe(u8, name),
        .index = if (index_str) |v| parseU32(v) else null,
        .kind = parseKind(kind_str),
        .mac_address = address,
        .operstate = parseOperstate(operstate_str),
        .mtu = if (mtu_str) |v| parseU32(v) else null,
        .carrier = parseCarrier(carrier_str),
        .speed_mbps = if (speed_str) |v| parseU32(v) else null,
        .rx_bytes = if (rx_str) |v| parseU64(v) else null,
        .tx_bytes = if (tx_str) |v| parseU64(v) else null,
        .flags_hex = flags_str,
    };
}

fn readSnapshot(gpa: std.mem.Allocator, sys_class_net: []const u8) !Snapshot {
    var interfaces = MyArrayList(Interface).init(gpa);
    errdefer {
        for (interfaces.items()) |iface| freeInterface(gpa, iface);
        interfaces.deinit();
    }

    var path_buf: [4096]u8 = undefined;
    const sys_class_net_z = pathToZ(sys_class_net, &path_buf) orelse return error.NameTooLong;
    const base_fd = sysOpen(sys_class_net_z, .{ .DIRECTORY = true, .CLOEXEC = true }, 0) catch |err| {
        if (err == error.FileNotFound) return Snapshot{ .generated_unix_ms = nowUnixMs(), .interfaces = &.{} };
        return err;
    };
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
                    const iface = try readInterface(gpa, base_fd, name);
                    try interfaces.append(iface);
                }
            }
            offset += entry.reclen;
        }
    }

    std.mem.sort(Interface, interfaces.items(), {}, lessThan);

    return Snapshot{
        .generated_unix_ms = nowUnixMs(),
        .interfaces = try interfaces.toOwnedSlice(),
    };
}

fn lessThan(_: void, a: Interface, b: Interface) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn freeInterface(gpa: std.mem.Allocator, iface: Interface) void {
    gpa.free(iface.name);
    if (iface.mac_address) |v| gpa.free(v);
    if (iface.flags_hex) |v| gpa.free(v);
}

fn freeSnapshot(gpa: std.mem.Allocator, snapshot: Snapshot) void {
    for (snapshot.interfaces) |iface| freeInterface(gpa, iface);
    gpa.free(snapshot.interfaces);
}

fn writeJsonValue(gpa: std.mem.Allocator, out: anytype, comptime T: type, value: ?T, comptime key: []const u8, comptime is_last: bool) !void {
    if (value == null) return;
    const fmt_str = "  \"" ++ key ++ "\": ";
    try out.appendSlice(fmt_str);
    const v = value.?;
    switch (@TypeOf(v)) {
        u64, u32 => {
            const num = try std.fmt.allocPrint(gpa, "{d}", .{v});
            defer gpa.free(num);
            try out.appendSlice(num);
        },
        bool => try out.appendSlice(if (v) "true" else "false"),
        []const u8 => {
            try out.append('"');
            try out.appendSlice(v);
            try out.append('"');
        },
        else => @compileError("unsupported type"),
    }
    if (!is_last) try out.append(',');
    try out.append('\n');
}

fn renderJson(gpa: std.mem.Allocator, snapshot: Snapshot) ![]const u8 {
    var out = MyArrayList(u8).init(gpa);
    errdefer out.deinit();

    try out.appendSlice("{\n");
    const header = try std.fmt.allocPrint(gpa, "  \"generated_unix_ms\": {d},\n", .{snapshot.generated_unix_ms});
    defer gpa.free(header);
    try out.appendSlice(header);
    try out.appendSlice("  \"interfaces\": [\n");
    for (snapshot.interfaces, 0..) |iface, idx| {
        const last = idx == snapshot.interfaces.len - 1;
        try out.appendSlice("    {\n");
        try out.appendSlice("      \"name\": \"");
        try out.appendSlice(iface.name);
        try out.appendSlice("\",\n");
        try writeJsonValue(gpa, &out, u32, iface.index, "index", false);
        try out.appendSlice("      \"kind\": \"");
        try out.appendSlice(iface.kind);
        try out.appendSlice("\",\n");
        try writeJsonValue(gpa, &out, []const u8, iface.mac_address, "mac-address", false);
        try out.appendSlice("      \"operstate\": \"");
        try out.appendSlice(iface.operstate);
        try out.appendSlice("\",\n");
        try writeJsonValue(gpa, &out, u32, iface.mtu, "mtu", false);
        try writeJsonValue(gpa, &out, bool, iface.carrier, "carrier", false);
        try writeJsonValue(gpa, &out, u32, iface.speed_mbps, "speed-mbps", false);
        try writeJsonValue(gpa, &out, u64, iface.rx_bytes, "rx-bytes", false);
        try writeJsonValue(gpa, &out, u64, iface.tx_bytes, "tx-bytes", false);
        try writeJsonValue(gpa, &out, []const u8, iface.flags_hex, "flags-hex", true);
        try out.appendSlice("    }");
        if (!last) try out.append(',');
        try out.append('\n');
    }
    try out.appendSlice("  ]\n");
    try out.append('}');
    try out.append('\n');
    return try out.toOwnedSlice();
}

fn renderRuntimeEnv(gpa: std.mem.Allocator, snapshot: Snapshot) ![]const u8 {
    var default_iface: []const u8 = "";
    for (snapshot.interfaces) |iface| {
        if (!std.mem.eql(u8, iface.name, "lo") and std.mem.eql(u8, iface.operstate, "up")) {
            default_iface = iface.name;
            break;
        }
    }
    if (default_iface.len == 0) {
        for (snapshot.interfaces) |iface| {
            if (std.mem.eql(u8, iface.operstate, "up")) {
                default_iface = iface.name;
                break;
            }
        }
    }
    var up_count: usize = 0;
    for (snapshot.interfaces) |iface| {
        if (std.mem.eql(u8, iface.operstate, "up")) up_count += 1;
    }
    return std.fmt.allocPrint(gpa, "ALPENGLOW_NETD_INTERFACES={d}\nALPENGLOW_NETD_UP_INTERFACES={d}\nALPENGLOW_NETD_DEFAULT_INTERFACE={s}\nALPENGLOW_NETD_GENERATED_UNIX_MS={d}\n", .{
        snapshot.interfaces.len,
        up_count,
        default_iface,
        snapshot.generated_unix_ms,
    });
}

fn writeSnapshot(gpa: std.mem.Allocator, snapshot: Snapshot, state_json: []const u8, runtime_env: []const u8) !void {
    const json = try renderJson(gpa, snapshot);
    defer gpa.free(json);
    const env = try renderRuntimeEnv(gpa, snapshot);
    defer gpa.free(env);

    if (std.fs.path.dirname(state_json)) |parent| makePathRecursive(parent) catch {};
    try writeFile(state_json, json);

    if (std.fs.path.dirname(runtime_env)) |parent| makePathRecursive(parent) catch {};
    try writeFile(runtime_env, env);
}

fn updateSnapshot(gpa: std.mem.Allocator, sys_class_net: []const u8, state_json: []const u8, runtime_env: []const u8) !void {
    const snapshot = try readSnapshot(gpa, sys_class_net);
    defer freeSnapshot(gpa, snapshot);
    try writeSnapshot(gpa, snapshot, state_json, runtime_env);
}

fn updateSnapshotScoped(gpa: std.mem.Allocator, sys_class_net: []const u8, state_json: []const u8, runtime_env: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    try updateSnapshot(allocator, sys_class_net, state_json, runtime_env);
}

fn sleepSeconds(seconds: u64) void {
    var req: linux.timespec = .{ .sec = @intCast(seconds), .nsec = 0 };
    var rem: linux.timespec = undefined;
    while (true) {
        const rc = linux.nanosleep(&req, &rem);
        if (getErrno(rc) == .SUCCESS) break;
        if (rem.sec <= 0 and rem.nsec <= 0) break;
        req = rem;
    }
}

fn watchLoop(gpa: std.mem.Allocator, sys_class_net: []const u8, state_json: []const u8, runtime_env: []const u8) !void {
    try updateSnapshotScoped(gpa, sys_class_net, state_json, runtime_env);
    while (true) {
        sleepSeconds(2);
        try updateSnapshotScoped(gpa, sys_class_net, state_json, runtime_env);
    }
}

fn envOrDefault(key: []const u8, default: []const u8) []const u8 {
    return getenv(key) orelse default;
}

fn nowUnixMs() u64 {
    var ts: linux.timespec = undefined;
    const rc = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
    if (getErrno(rc) != .SUCCESS) return 0;
    if (ts.sec < 0 or ts.nsec < 0) return 0;
    const sec: u64 = @intCast(ts.sec);
    const nsec: u64 = @intCast(ts.nsec);
    return sec * 1000 + nsec / 1_000_000;
}

fn writeStderr(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const sys_class_net = envOrDefault("ALPENGLOW_NETD_SYS_CLASS_NET", DEFAULT_SYS_CLASS_NET);
    const state_json = envOrDefault("ALPENGLOW_NETD_STATE_JSON", DEFAULT_STATE_JSON);
    const runtime_env = envOrDefault("ALPENGLOW_NETD_RUNTIME_ENV", DEFAULT_RUNTIME_ENV);

    watchLoop(allocator, sys_class_net, state_json, runtime_env) catch |err| {
        writeStderr("alpenglow-netd-zig: ");
        writeStderr(@errorName(err));
        writeStderr("\n");
        std.process.exit(1);
    };
}
