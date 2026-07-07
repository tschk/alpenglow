const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });
    const common = b.createModule(.{
        .root_source_file = b.path("../zig-common.zig"),
    });

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("common", common);

    const exe = b.addExecutable(.{
        .name = "alpenglow-kernelctl",
        .root_module = root_mod,
    });
    exe.root_module.link_libc = false;

    const strip = b.option(bool, "strip", "Strip debug symbols") orelse (optimize == .ReleaseSmall);
    exe.root_module.strip = strip;

    b.installArtifact(exe);

    // Tests
    const main_tests = b.addTest(.{
        .root_module = root_mod,
    });
    main_tests.root_module.link_libc = true;
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
