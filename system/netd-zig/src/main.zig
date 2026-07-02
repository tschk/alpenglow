const std = @import("std");

const DEFAULT_SYS_CLASS_NET = "/sys/class/net";
const DEFAULT_STATE_JSON = "/run/alpenglow/netd/interfaces.json";
const DEFAULT_RUNTIME_ENV = "/run/alpenglow/netd/runtime-state.env";

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

fn readTrimmed(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, sub_path: []const u8) ?[]const u8 {
    const content = dir.readFileAlloc(io, sub_path, gpa, std.Io.Limit.limited(4096)) catch return null;
    defer gpa.free(content);
    const trimmed = std.mem.trim(u8, content, " \t\r\n");
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

fn readInterface(io: std.Io, gpa: std.mem.Allocator, base_dir: std.Io.Dir, name: []const u8) !Interface {
    const iface_dir = try base_dir.openDir(io, name, .{});
    defer iface_dir.close(io);

    const index_str = readTrimmed(io, gpa, iface_dir, "ifindex");
    const kind_str = readTrimmed(io, gpa, iface_dir, "type");
    const address = readTrimmed(io, gpa, iface_dir, "address");
    const operstate_str = readTrimmed(io, gpa, iface_dir, "operstate");
    const mtu_str = readTrimmed(io, gpa, iface_dir, "mtu");
    const carrier_str = readTrimmed(io, gpa, iface_dir, "carrier");
    const speed_str = readTrimmed(io, gpa, iface_dir, "speed");
    const rx_str = readTrimmed(io, gpa, iface_dir, "statistics/rx_bytes");
    const tx_str = readTrimmed(io, gpa, iface_dir, "statistics/tx_bytes");
    const flags_str = readTrimmed(io, gpa, iface_dir, "flags");

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

fn readSnapshot(io: std.Io, gpa: std.mem.Allocator, sys_class_net: []const u8) !Snapshot {
    var interfaces = std.ArrayList(Interface).empty;
    errdefer {
        for (interfaces.items) |iface| freeInterface(gpa, iface);
        interfaces.deinit(gpa);
    }

    const dir = std.Io.Dir.cwd().openDir(io, sys_class_net, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return Snapshot{ .generated_unix_ms = nowUnixMs(), .interfaces = &.{} };
        return err;
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const iface = try readInterface(io, gpa, dir, entry.name);
        try interfaces.append(gpa, iface);
    }

    std.mem.sort(Interface, interfaces.items, {}, lessThan);

    return Snapshot{
        .generated_unix_ms = nowUnixMs(),
        .interfaces = try interfaces.toOwnedSlice(gpa),
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

fn writeJsonValue(gpa: std.mem.Allocator, out: *std.ArrayList(u8), comptime T: type, value: ?T, comptime key: []const u8, comptime is_last: bool) !void {
    if (value == null) return;
    const fmt_str = "  \"" ++ key ++ "\": ";
    try out.appendSlice(gpa, fmt_str);
    const v = value.?;
    switch (@TypeOf(v)) {
        u64, u32 => {
            const num = try std.fmt.allocPrint(gpa, "{d}", .{v});
            defer gpa.free(num);
            try out.appendSlice(gpa, num);
        },
        bool => try out.appendSlice(gpa, if (v) "true" else "false"),
        []const u8 => {
            try out.append(gpa, '"');
            try out.appendSlice(gpa, v);
            try out.append(gpa, '"');
        },
        else => @compileError("unsupported type"),
    }
    if (!is_last) try out.append(gpa, ',');
    try out.append(gpa, '\n');
}

fn renderJson(gpa: std.mem.Allocator, snapshot: Snapshot) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(gpa);

    try out.appendSlice(gpa, "{\n");
    const header = try std.fmt.allocPrint(gpa, "  \"generated_unix_ms\": {d},\n", .{snapshot.generated_unix_ms});
    defer gpa.free(header);
    try out.appendSlice(gpa, header);
    try out.appendSlice(gpa, "  \"interfaces\": [\n");
    for (snapshot.interfaces, 0..) |iface, idx| {
        const last = idx == snapshot.interfaces.len - 1;
        try out.appendSlice(gpa, "    {\n");
        try out.appendSlice(gpa, "      \"name\": \"");
        try out.appendSlice(gpa, iface.name);
        try out.appendSlice(gpa, "\",\n");
        try writeJsonValue(gpa, &out, u32, iface.index, "index", false);
        try out.appendSlice(gpa, "      \"kind\": \"");
        try out.appendSlice(gpa, iface.kind);
        try out.appendSlice(gpa, "\",\n");
        try writeJsonValue(gpa, &out, []const u8, iface.mac_address, "mac-address", false);
        try out.appendSlice(gpa, "      \"operstate\": \"");
        try out.appendSlice(gpa, iface.operstate);
        try out.appendSlice(gpa, "\",\n");
        try writeJsonValue(gpa, &out, u32, iface.mtu, "mtu", false);
        try writeJsonValue(gpa, &out, bool, iface.carrier, "carrier", false);
        try writeJsonValue(gpa, &out, u32, iface.speed_mbps, "speed-mbps", false);
        try writeJsonValue(gpa, &out, u64, iface.rx_bytes, "rx-bytes", false);
        try writeJsonValue(gpa, &out, u64, iface.tx_bytes, "tx-bytes", false);
        try writeJsonValue(gpa, &out, []const u8, iface.flags_hex, "flags-hex", true);
        try out.appendSlice(gpa, "    }");
        if (!last) try out.append(gpa, ',');
        try out.append(gpa, '\n');
    }
    try out.appendSlice(gpa, "  ]\n");
    try out.append(gpa, '}');
    try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
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

fn writeSnapshot(io: std.Io, gpa: std.mem.Allocator, snapshot: Snapshot, state_json: []const u8, runtime_env: []const u8) !void {
    const json = try renderJson(gpa, snapshot);
    defer gpa.free(json);
    const env = try renderRuntimeEnv(gpa, snapshot);
    defer gpa.free(env);

    std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(state_json) orelse "/") catch {};
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = state_json, .data = json });

    std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(runtime_env) orelse "/") catch {};
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = runtime_env, .data = env });
}

fn updateSnapshot(io: std.Io, gpa: std.mem.Allocator, sys_class_net: []const u8, state_json: []const u8, runtime_env: []const u8) !void {
    const snapshot = try readSnapshot(io, gpa, sys_class_net);
    defer freeSnapshot(gpa, snapshot);
    try writeSnapshot(io, gpa, snapshot, state_json, runtime_env);
}

fn updateSnapshotScoped(io: std.Io, gpa: std.mem.Allocator, sys_class_net: []const u8, state_json: []const u8, runtime_env: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    try updateSnapshot(io, allocator, sys_class_net, state_json, runtime_env);
}

fn sleepSeconds(seconds: u64) void {
    var req: std.os.linux.timespec = .{ .sec = @intCast(seconds), .nsec = 0 };
    var rem: std.os.linux.timespec = undefined;
    while (true) {
        const rc = std.os.linux.nanosleep(&req, &rem);
        if (rc == 0) break;
        if (rem.sec <= 0 and rem.nsec <= 0) break;
        req = rem;
    }
}

fn watchLoop(io: std.Io, gpa: std.mem.Allocator, sys_class_net: []const u8, state_json: []const u8, runtime_env: []const u8) !void {
    try updateSnapshotScoped(io, gpa, sys_class_net, state_json, runtime_env);
    while (true) {
        sleepSeconds(2);
        try updateSnapshotScoped(io, gpa, sys_class_net, state_json, runtime_env);
    }
}

fn envOrDefault(environ: std.process.Environ, key: []const u8, default: []const u8) []const u8 {
    return environ.getPosix(key) orelse default;
}

fn nowUnixMs() u64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(std.os.linux.clockid_t.REALTIME, &ts);
    if (rc != 0) return 0;
    if (ts.sec < 0 or ts.nsec < 0) return 0;
    const sec: u64 = @intCast(ts.sec);
    const nsec: u64 = @intCast(ts.nsec);
    return sec * 1000 + nsec / 1_000_000;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const sys_class_net = envOrDefault(init.minimal.environ, "ALPENGLOW_NETD_SYS_CLASS_NET", DEFAULT_SYS_CLASS_NET);
    const state_json = envOrDefault(init.minimal.environ, "ALPENGLOW_NETD_STATE_JSON", DEFAULT_STATE_JSON);
    const runtime_env = envOrDefault(init.minimal.environ, "ALPENGLOW_NETD_RUNTIME_ENV", DEFAULT_RUNTIME_ENV);

    watchLoop(io, gpa, sys_class_net, state_json, runtime_env) catch |err| {
        std.Io.File.stderr().writeStreamingAll(io, "alpenglow-netd-zig: ") catch {};
        std.Io.File.stderr().writeStreamingAll(io, @errorName(err)) catch {};
        std.Io.File.stderr().writeStreamingAll(io, "\n") catch {};
        std.process.exit(1);
    };
}
