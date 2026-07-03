const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });
    const exe = b.addExecutable(.{
        .name = "alpenglow-netd-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.link_libc = true;

    const strip = b.option(bool, "strip", "Strip debug symbols") orelse (optimize == .ReleaseSmall);
    exe.root_module.strip = strip;

    b.installArtifact(exe);
}
