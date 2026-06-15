const std = @import("std");

pub fn main() void {
    // syscall(open, "/dev/console", O_WRONLY|O_NOCTTY, 0)
    const path = "/dev/console";
    const fd = std.os.linux.syscall3(.open, @intFromPtr(path), 0x101, 0);
    
    if (fd == 0 or fd > 0) {
        const msg1 = "Alpenglow Zig init boot OK\n";
        const msg2 = "login:\n";
        _ = std.os.linux.syscall3(.write, fd, @intFromPtr(msg1.ptr), msg1.len);
        _ = std.os.linux.syscall3(.write, fd, @intFromPtr(msg2.ptr), msg2.len);
        _ = std.os.linux.syscall1(.close, fd);
    }
    
    _ = std.os.linux.syscall0(.sync);
    _ = std.os.linux.syscall3(.reboot, 0xfee1dead, 0x28121969, 0x4321fedc);
    
    while (true) {}
}
