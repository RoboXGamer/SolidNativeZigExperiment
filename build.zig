const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const raylib = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const module = b.addModule("draft1", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("raylib", raylib.module("raylib"));
    module.linkLibrary(raylib.artifact("raylib"));
    module.addIncludePath(b.path("vendor/quickjs"));
    module.addCSourceFiles(.{
        .files = &.{ "src/quickjs_bridge.c", "vendor/quickjs/cutils.c", "vendor/quickjs/dtoa.c", "vendor/quickjs/libregexp.c", "vendor/quickjs/libunicode.c", "vendor/quickjs/quickjs.c" },
        .flags = &.{ "-D_GNU_SOURCE", "-DWIN32_LEAN_AND_MEAN", "-D_WIN32_WINNT=0x0601" },
    });
    module.link_libc = true;
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
