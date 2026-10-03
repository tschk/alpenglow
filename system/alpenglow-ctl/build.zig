const std = @import("std");

fn createCtlModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    common: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("common", common);
    return mod;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const common = b.createModule(.{
        .root_source_file = b.path("../zig-common.zig"),
    });

    const kernel_mod = createCtlModule(b, "src/kernel.zig", target, optimize, common);
    const network_mod = createCtlModule(b, "src/network.zig", target, optimize, common);
    const pressure_mod = createCtlModule(b, "src/pressure.zig", target, optimize, common);
    const zram_mod = createCtlModule(b, "src/zram.zig", target, optimize, common);
    const main_mod = createCtlModule(b, "src/main.zig", target, optimize, common);

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

    const host_target = b.graph.host;

    const kernel_test_mod = createCtlModule(b, "src/kernel.zig", host_target, optimize, common);
    const kernel_tests = b.addTest(.{ .root_module = kernel_test_mod });
    kernel_tests.root_module.link_libc = true;
    const run_kernel_tests = b.addRunArtifact(kernel_tests);

    const common_test_mod = b.createModule(.{
        .root_source_file = b.path("../zig-common.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const common_tests = b.addTest(.{ .root_module = common_test_mod });
    common_tests.root_module.link_libc = true;
    const run_common_tests = b.addRunArtifact(common_tests);

    const pressure_test_mod = createCtlModule(b, "src/pressure.zig", host_target, optimize, common);
    const pressure_tests = b.addTest(.{ .root_module = pressure_test_mod });
    pressure_tests.root_module.link_libc = true;
    const run_pressure_tests = b.addRunArtifact(pressure_tests);

    const test_step = b.step("test", "Run alpenglow-ctl tests");
    test_step.dependOn(&run_kernel_tests.step);
    test_step.dependOn(&run_common_tests.step);
    test_step.dependOn(&run_pressure_tests.step);

    const main_test_mod = createCtlModule(b, "src/main.zig", host_target, optimize, common);
    main_test_mod.addImport("kernel", kernel_mod);
    main_test_mod.addImport("network", network_mod);
    main_test_mod.addImport("pressure", pressure_mod);
    main_test_mod.addImport("zram", zram_mod);

    const main_tests = b.addTest(.{ .root_module = main_test_mod });
    main_tests.root_module.link_libc = true;
    const run_main_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_main_tests.step);
}
