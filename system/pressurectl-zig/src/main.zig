const std = @import("std");

const DEFAULT_PRESSURE_PATH = "/proc/pressure/memory";
const DEFAULT_STATE_JSON = "/run/alpenglow/pressure/pressure.json";

const Pressure = struct {
    avg10: ?f64 = null,
    avg60: ?f64 = null,
    avg300: ?f64 = null,
    total: ?u64 = null,
};

fn readPressure(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !Pressure {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, std.Io.Limit.limited(1024));
    defer gpa.free(content);
    var p = Pressure{};
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "some ")) continue;
        var it = std.mem.splitScalar(u8, line["some ".len..], ' ');
        while (it.next()) |part| {
            if (std.mem.startsWith(u8, part, "avg10=")) {
                p.avg10 = std.fmt.parseFloat(f64, part["avg10=".len..]) catch null;
            } else if (std.mem.startsWith(u8, part, "avg60=")) {
                p.avg60 = std.fmt.parseFloat(f64, part["avg60=".len..]) catch null;
            } else if (std.mem.startsWith(u8, part, "avg300=")) {
                p.avg300 = std.fmt.parseFloat(f64, part["avg300=".len..]) catch null;
            } else if (std.mem.startsWith(u8, part, "total=")) {
                p.total = std.fmt.parseInt(u64, part["total=".len..], 10) catch null;
            }
        }
    }
    return p;
}

fn renderJson(gpa: std.mem.Allocator, p: Pressure) ![]const u8 {
    return std.fmt.allocPrint(gpa, "{{\"memory_some_avg10\":{d:.4},\"memory_some_avg60\":{d:.4},\"memory_some_avg300\":{d:.4},\"memory_some_total\":{d}}}\n", .{
        p.avg10 orelse 0,
        p.avg60 orelse 0,
        p.avg300 orelse 0,
        p.total orelse 0,
    });
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

fn update(io: std.Io, gpa: std.mem.Allocator, pressure_path: []const u8, state_json: []const u8) !void {
    const p = readPressure(io, gpa, pressure_path) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    const json = try renderJson(gpa, p);
    defer gpa.free(json);
    std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(state_json) orelse "/") catch {};
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = state_json, .data = json });
}

fn envOrDefault(environ: std.process.Environ, key: []const u8, default: []const u8) []const u8 {
    return environ.getPosix(key) orelse default;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const pressure_path = envOrDefault(init.minimal.environ, "ALPENGLOW_PRESSURECTL_PATH", DEFAULT_PRESSURE_PATH);
    const state_json = envOrDefault(init.minimal.environ, "ALPENGLOW_PRESSURECTL_STATE_JSON", DEFAULT_STATE_JSON);

    while (true) {
        update(io, gpa, pressure_path, state_json) catch |err| {
            std.Io.File.stderr().writeStreamingAll(io, "pressurectl: ") catch {};
            std.Io.File.stderr().writeStreamingAll(io, @errorName(err)) catch {};
            std.Io.File.stderr().writeStreamingAll(io, "\n") catch {};
        };
        sleepSeconds(60);
    }
}
