const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const raylib = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const ui_core = b.addModule("ui_core", .{
        .root_source_file = b.path("modules/ui_core/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const solid_bridge = b.addModule("solid_bridge", .{
        .root_source_file = b.path("modules/solid_bridge/root.zig"),
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
    module.linkLibrary(raylib.artifact("raylib"));
    module.addCSourceFile(.{ .file = b.path("src/hmr_watcher.c"), .flags = &.{} });
    solid_bridge.addIncludePath(b.path("vendor/quickjs"));
    solid_bridge.addCSourceFiles(.{
        .files = &.{ "modules/solid_bridge/quickjs_bridge.c", "vendor/quickjs/cutils.c", "vendor/quickjs/dtoa.c", "vendor/quickjs/libregexp.c", "vendor/quickjs/libunicode.c", "vendor/quickjs/quickjs.c" },
        .flags = &.{ "-D_GNU_SOURCE", "-DWIN32_LEAN_AND_MEAN", "-D_WIN32_WINNT=0x0601" },
    });
    solid_bridge.link_libc = true;
    const tests = b.addTest(.{ .root_module = ui_core });
    const test_step = b.step("test", "Run UI core tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const exe = b.addExecutable(.{
        .name = "windows",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("draft1", module);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the window");
    run_step.dependOn(&run.step);
}
