const std = @import("std");

pub const Options = struct {
    source: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn addModule(b: *std.Build, options: Options) *std.Build.Module {
    return b.addModule("ui_core", .{ .root_source_file = options.source, .target = options.target, .optimize = options.optimize });
}

pub fn build(b: *std.Build) void {
    const module = addModule(b, .{ .source = b.path("root.zig"), .target = b.standardTargetOptions(.{}), .optimize = b.standardOptimizeOption(.{}) });
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run the UI core tests").dependOn(&b.addRunArtifact(tests).step);
}
