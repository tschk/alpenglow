const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

/// ArrayList compatibility shim for Zig 0.14/0.15/0.16 API differences.
pub fn MyArrayList(comptime T: type) type {
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

pub const SyscallError = error{
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

pub fn getErrno(rc: usize) linux.E {
    const signed: isize = @bitCast(rc);
    if (signed > -4096 and signed < 0) {
        return @enumFromInt(-signed);
    }
    return .SUCCESS;
}

pub fn checkSyscall(rc: usize) SyscallError!void {
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

pub fn pathToZ(path: []const u8, buf: []u8) ?[:0]const u8 {
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

pub fn sysOpen(path: [*:0]const u8, flags: linux.O, mode: linux.mode_t) SyscallError!i32 {
    const rc = linux.open(path, flags, mode);
    try checkSyscall(rc);
    return @intCast(rc);
}

pub fn sysOpenat(dirfd: i32, path: [*:0]const u8, flags: linux.O, mode: linux.mode_t) SyscallError!i32 {
    const rc = linux.openat(dirfd, path, flags, mode);
    try checkSyscall(rc);
    return @intCast(rc);
}

pub fn sysRead(fd: i32, buf: []u8) SyscallError!usize {
    const rc = linux.read(fd, buf.ptr, buf.len);
    try checkSyscall(rc);
    return rc;
}

pub fn sysWrite(fd: i32, data: []const u8) SyscallError!void {
    var written: usize = 0;
    while (written < data.len) {
        const rc = linux.write(fd, data.ptr + written, data.len - written);
        try checkSyscall(rc);
        written += rc;
    }
}

pub fn sysClose(fd: i32) void {
    _ = linux.close(fd);
}

pub fn sysMkdir(path: [*:0]const u8, mode: linux.mode_t) SyscallError!void {
    const rc = linux.mkdir(path, mode);
    if (getErrno(rc) == .EXIST) return;
    try checkSyscall(rc);
}

pub fn sysGetdents64(fd: i32, buf: []u8) SyscallError!usize {
    const rc = linux.getdents64(fd, buf.ptr, buf.len);
    try checkSyscall(rc);
    return rc;
}

pub fn fileExists(path: []const u8) bool {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return false;
    const rc = linux.access(path_z, linux.F_OK);
    return getErrno(rc) == .SUCCESS;
}

pub fn makeDir(path: []const u8) SyscallError!void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    try sysMkdir(path_z, 0o755);
}

pub fn makePathRecursive(path: []const u8) !void {
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

pub fn readFileLimited(allocator: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    var path_buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &path_buf) orelse return error.NameTooLong;
    const fd = try sysOpen(path_z, .{ .CLOEXEC = true }, 0);
    defer sysClose(fd);
    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    var out = MyArrayList(u8).init(allocator);
    errdefer out.deinit();
    while (true) {
        const n = try sysRead(fd, &buf);
        if (n == 0) break;
        const slice = buf[0..n];
        if (total + n > max) return error.FileTooBig;
        try out.appendSlice(slice);
        total += n;
    }
    return try out.toOwnedSlice();
}

pub fn writeFile(path: []const u8, data: []const u8, truncate: bool) !void {
    var buf: [4096]u8 = undefined;
    const path_z = pathToZ(path, &buf) orelse return error.NameTooLong;
    var flags: linux.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .CLOEXEC = true };
    if (truncate) flags.TRUNC = true;
    const fd = try sysOpen(path_z, flags, 0o644);
    defer sysClose(fd);
    try sysWrite(fd, data);
}

pub fn writeStderr(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

test "sysOpen" {
    const testing = std.testing;

    const path = "/tmp/test_sysopen_file.txt";

    // Ensure cleanup before and after
    _ = linux.unlink(path);
    defer _ = linux.unlink(path);

    // 1. Test opening non-existent file (should fail with error.FileNotFound)
    const err = sysOpen(path, .{ .ACCMODE = .RDONLY }, 0);
    try testing.expectError(error.FileNotFound, err);

    // 2. Test creating a file (should succeed and return valid fd)
    const fd1 = try sysOpen(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    try testing.expect(fd1 >= 0);
    sysClose(fd1);

    // 3. Test opening the existing file (should succeed and return valid fd)
    const fd2 = try sysOpen(path, .{ .ACCMODE = .RDONLY }, 0);
    try testing.expect(fd2 >= 0);
    sysClose(fd2);
}
