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

    const logrotate_mod = b.createModule(.{
        .root_source_file = b.path("src/logrotate.zig"),
        .target = target,
        .optimize = optimize,
    });
    logrotate_mod.addImport("common", common);

    const network_mod = b.createModule(.{
        .root_source_file = b.path("src/network.zig"),
        .target = target,
        .optimize = optimize,
    });
    network_mod.addImport("common", common);

    const power_mod = b.createModule(.{
        .root_source_file = b.path("src/power.zig"),
        .target = target,
        .optimize = optimize,
    });
    power_mod.addImport("common", common);

    const pressure_mod = b.createModule(.{
        .root_source_file = b.path("src/pressure.zig"),
        .target = target,
        .optimize = optimize,
    });
    pressure_mod.addImport("common", common);

    const role_mod = b.createModule(.{
        .root_source_file = b.path("src/role.zig"),
        .target = target,
        .optimize = optimize,
    });
    role_mod.addImport("common", common);

    const state_mod = b.createModule(.{
        .root_source_file = b.path("src/state.zig"),
        .target = target,
        .optimize = optimize,
    });
    state_mod.addImport("common", common);

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
    main_mod.addImport("logrotate", logrotate_mod);
    main_mod.addImport("network", network_mod);
    main_mod.addImport("power", power_mod);
    main_mod.addImport("pressure", pressure_mod);
    main_mod.addImport("role", role_mod);
    main_mod.addImport("state", state_mod);
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
        "alpenglow-role-publish",
        "alpenglow-powerctl",
        "alpenglow-state-mount",
        "alpenglow-logrotate",
    };
    for (compat_names) |name| {
        const install = b.addInstallArtifact(exe, .{
            .dest_sub_path = name,
        });
        b.getInstallStep().dependOn(&install.step);
    }

    const test_step = b.step("test", "Run alpenglow-ctl tests");

    const common_test_mod = b.createModule(.{
        .root_source_file = b.path("../zig-common.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const common_tests = b.addTest(.{ .root_module = common_test_mod });
    common_tests.root_module.link_libc = true;
    test_step.dependOn(&b.addRunArtifact(common_tests).step);

    const test_sources = [_][]const u8{
        "src/kernel.zig",
        "src/logrotate.zig",
        "src/network.zig",
        "src/power.zig",
        "src/pressure.zig",
        "src/role.zig",
        "src/state.zig",
        "src/zram.zig",
    };
    for (test_sources) |src_path| {
        const mod = b.createModule(.{
            .root_source_file = b.path(src_path),
            .target = b.graph.host,
            .optimize = optimize,
        });
        mod.addImport("common", common);
        const unit_tests = b.addTest(.{ .root_module = mod });
        unit_tests.root_module.link_libc = true;
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }

    const main_test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    main_test_mod.addImport("common", common);
    main_test_mod.addImport("kernel", kernel_mod);
    main_test_mod.addImport("logrotate", logrotate_mod);
    main_test_mod.addImport("network", network_mod);
    main_test_mod.addImport("power", power_mod);
    main_test_mod.addImport("pressure", pressure_mod);
    main_test_mod.addImport("role", role_mod);
    main_test_mod.addImport("state", state_mod);
    main_test_mod.addImport("zram", zram_mod);

    const main_tests = b.addTest(.{
        .root_module = main_test_mod,
    });
    main_tests.root_module.link_libc = true;
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
}
