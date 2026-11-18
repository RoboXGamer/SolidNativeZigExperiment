const std = @import("std");
const core_build = @import("modules/ui_core/build.zig");
const bridge_build = @import("modules/solid_bridge/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const driver_enabled = b.option(bool, "driver", "Enable the local development/test driver") orelse false;
    const raylib = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const ui_core = core_build.addModule(b, .{
        .source = b.path("modules/ui_core/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const solid_bridge = bridge_build.addModule(b, .{
        .probes = driver_enabled,
        .optimize_quickjs = b.option(bool, "quickjs-optimize", "Optimize QuickJS C interpreter even in Debug builds") orelse true,
        .source = b.path("modules/solid_bridge/root.zig"),
        .c_source = b.path("modules/solid_bridge/quickjs_bridge.c"),
        .quickjs_source = b.path("vendor/quickjs"),
        .target = target,
        .optimize = optimize,
    });
    const module = b.addModule("draft1", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("raylib", raylib.module("raylib"));
    module.addImport("ui_core", ui_core);
    module.addImport("solid_bridge", solid_bridge);
    const options = b.addOptions();
    options.addOption(bool, "driver", driver_enabled);
    module.addOptions("host_options", options);
    if (driver_enabled) {
        module.addCSourceFile(.{ .file = b.path("src/driver_pipe.c"), .flags = &.{} });
        module.linkSystemLibrary("advapi32", .{});
        module.linkSystemLibrary("bcrypt", .{});
    }
    module.addAnonymousImport("host_driver", .{ .root_source_file = b.path("modules/host_runtime/driver.zig") });
    module.addAnonymousImport("host_accounting", .{ .root_source_file = b.path("modules/host_runtime/accounting.zig") });
    module.addAnonymousImport("ui_bundle", .{
        .root_source_file = b.path(b.option([]const u8, "ui-bundle", "JavaScript bundle to embed") orelse "src/ui-bundle.js"),
    });
    module.linkLibrary(raylib.artifact("raylib"));
    module.addCSourceFile(.{ .file = b.path("src/hmr_watcher.c"), .flags = if (driver_enabled) &.{"-DUI_DRIVER=1"} else &.{} });
    module.addCSourceFile(.{ .file = b.path("src/event_wakeup.c"), .flags = &.{} });
    module.addCSourceFile(.{ .file = b.path("src/text_backend.cpp"), .flags = &.{ "-std=c++17", "-fno-exceptions" } });
    module.link_libcpp = true;
    module.addCSourceFile(.{ .file = b.path("src/cursor_backend.c"), .flags = &.{} });
    module.linkSystemLibrary("dwrite", .{});
    module.linkSystemLibrary("imm32", .{});
    const tests = b.addTest(.{ .root_module = ui_core });
    const test_step = b.step("test", "Run UI core tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const runtime_tests = b.addTest(.{ .root_module = solid_bridge });
    const protocol_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("modules/host_runtime/driver.zig"), .target = target, .optimize = optimize }) });
    const runtime_step = b.step("test-runtime", "Test the real QuickJS clock and driver protocol");
    runtime_step.dependOn(&b.addRunArtifact(runtime_tests).step);
    runtime_step.dependOn(&b.addRunArtifact(protocol_tests).step);
    const scheduler_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("modules/host_runtime/scheduler.zig"), .target = target, .optimize = optimize }) });
    runtime_step.dependOn(&b.addRunArtifact(scheduler_tests).step);
    const exe = b.addExecutable(.{
        .name = "windows",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("draft1", module);
    if (b.option(bool, "portable", "Build a Windows GUI executable without a console") orelse false) {
        exe.subsystem = .windows;
    }
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the window");
    run_step.dependOn(&run.step);
    const check_module = b.createModule(.{ .root_source_file = b.path("src/render_check.zig"), .target = target, .optimize = optimize });
    check_module.addImport("raylib", raylib.module("raylib"));
    check_module.addImport("ui_core", ui_core);
    check_module.linkLibrary(raylib.artifact("raylib"));
    check_module.addCSourceFile(.{ .file = b.path("src/text_backend.cpp"), .flags = &.{ "-std=c++17", "-fno-exceptions" } });
    check_module.link_libcpp = true;
    check_module.addCSourceFile(.{ .file = b.path("src/cursor_backend.c"), .flags = &.{} });
    check_module.linkSystemLibrary("dwrite", .{});
    check_module.linkSystemLibrary("imm32", .{});
    const native_check = b.addExecutable(.{ .name = "render-check", .root_module = check_module });
    b.step("test-native", "Check real OpenGL framebuffer pixels").dependOn(&b.addRunArtifact(native_check).step);
}
