const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const mod = b.createModule(.{
        .root_source_file = b.path("init.zig"),
        .target = target,
        .optimize = optimize,
    });

    const strip = b.option(bool, "strip", "Strip debug symbols") orelse (optimize == .ReleaseSmall);
    mod.strip = strip;

    const exe = b.addExecutable(.{
        .name = "alpenglow-init",
        .root_module = mod,
    });

    b.installArtifact(exe);
}
