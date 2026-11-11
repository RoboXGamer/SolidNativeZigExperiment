const std = @import("std");

pub const Options = struct {
    source: std.Build.LazyPath,
    c_source: std.Build.LazyPath,
    quickjs_source: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn addModule(b: *std.Build, options: Options) *std.Build.Module {
    const module = b.addModule("solid_bridge", .{ .root_source_file = options.source, .target = options.target, .optimize = options.optimize });
    module.addIncludePath(options.quickjs_source);
    const flags: []const []const u8 = if (options.target.result.os.tag == .windows)
        &.{ "-D_GNU_SOURCE", "-DWIN32_LEAN_AND_MEAN" }
    else
        &.{"-D_GNU_SOURCE"};
    module.addCSourceFile(.{ .file = options.c_source, .flags = flags });
    for ([_][]const u8{ "cutils.c", "dtoa.c", "libregexp.c", "libunicode.c", "quickjs.c" }) |file| {
        module.addCSourceFile(.{ .file = options.quickjs_source.path(b, file), .flags = flags });
    }
    module.link_libc = true;
    return module;
}

pub fn build(b: *std.Build) void {
    const source_dir = b.option([]const u8, "quickjs-source", "Absolute directory containing the pinned QuickJS-NG sources") orelse
        @panic("Supply -Dquickjs-source=<absolute directory>");
    _ = addModule(b, .{
        .source = b.path("root.zig"),
        .c_source = b.path("quickjs_bridge.c"),
        .quickjs_source = .{ .cwd_relative = source_dir },
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
}
