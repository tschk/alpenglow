const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const common = b.createModule(.{
        .root_source_file = b.path("../zig-common.zig"),
    });

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    kernel_mod.addImport("common", common);

    const network_mod = b.createModule(.{
        .root_source_file = b.path("src/network.zig"),
        .target = target,
        .optimize = optimize,
    });
    network_mod.addImport("common", common);

    const pressure_mod = b.createModule(.{
        .root_source_file = b.path("src/pressure.zig"),
        .target = target,
        .optimize = optimize,
    });
    pressure_mod.addImport("common", common);

    const zram_mod = b.createModule(.{
        .root_source_file = b.path("src/zram.zig"),
        .target = target,
        .optimize = optimize,
    });
    zram_mod.addImport("common", common);

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addImport("common", common);
    main_mod.addImport("kernel", kernel_mod);
    main_mod.addImport("network", network_mod);
    main_mod.addImport("pressure", pressure_mod);
    main_mod.addImport("zram", zram_mod);

    const exe = b.addExecutable(.{
        .name = "alpenglow-ctl",
        .root_module = main_mod,
    });
    exe.root_module.link_libc = true;

    const strip = b.option(bool, "strip", "Strip debug symbols") orelse (optimize == .ReleaseSmall);
    exe.root_module.strip = strip;

    const compat_names = [_][]const u8{
        "alpenglow-ctl",
        "alpenglow-kernelctl",
        "alpenglow-netd-zig",
        "alpenglow-pressurectl-zig",
        "alpenglow-zramctl-zig",
    };
    for (compat_names) |name| {
        const install = b.addInstallArtifact(exe, .{
            .dest_sub_path = name,
        });
        b.getInstallStep().dependOn(&install.step);
    }

    const kernel_test_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    kernel_test_mod.addImport("common", common);

    const kernel_tests = b.addTest(.{
        .root_module = kernel_test_mod,
    });
    kernel_tests.root_module.link_libc = true;
    const run_kernel_tests = b.addRunArtifact(kernel_tests);

    const test_step = b.step("test", "Run alpenglow-ctl tests");
    test_step.dependOn(&run_kernel_tests.step);
}
