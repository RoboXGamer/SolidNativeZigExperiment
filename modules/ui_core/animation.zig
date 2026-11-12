//! CSS transition timing and value interpolation.
const std = @import("std");
const transform_mod = @import("transform.zig");
const easing = @import("easing.zig");
pub const Matrix2D = transform_mod.Matrix2D;
pub const CubicBezier = easing.CubicBezier;
pub const Timing = easing.Timing;
pub const LinearPoint = easing.LinearPoint;
pub const LinearEasing = easing.LinearEasing;
pub const ParseError = easing.ParseError;
pub const parseTimingFunctionStrict = easing.parseTimingFunctionStrict;
pub const parseTimingFunction = easing.parseTimingFunction;

pub fn interpolateNumber(from: f32, to: f32, progress: f32) f32 {
    return from + (to - from) * progress;
}
pub fn interpolateColor(from: [4]u8, to: [4]u8, progress: f32) [4]u8 {
    const p = std.math.clamp(progress, 0.0, 1.0);
    return .{
        @intFromFloat(@as(f32, @floatFromInt(from[0])) * (1.0 - p) + @as(f32, @floatFromInt(to[0])) * p),
        @intFromFloat(@as(f32, @floatFromInt(from[1])) * (1.0 - p) + @as(f32, @floatFromInt(to[1])) * p),
        @intFromFloat(@as(f32, @floatFromInt(from[2])) * (1.0 - p) + @as(f32, @floatFromInt(to[2])) * p),
        @intFromFloat(@as(f32, @floatFromInt(from[3])) * (1.0 - p) + @as(f32, @floatFromInt(to[3])) * p),
    };
}

pub fn interpolateMatrix(from: Matrix2D, to: Matrix2D, progress: f32) Matrix2D {
    const sx0 = @sqrt(from.a * from.a + from.b * from.b);
    const sx1 = @sqrt(to.a * to.a + to.b * to.b);
    if (sx0 < 0.00001 or sx1 < 0.00001) return .{ .a = interpolateNumber(from.a, to.a, progress), .b = interpolateNumber(from.b, to.b, progress), .c = interpolateNumber(from.c, to.c, progress), .d = interpolateNumber(from.d, to.d, progress), .tx = interpolateNumber(from.tx, to.tx, progress), .ty = interpolateNumber(from.ty, to.ty, progress) };
    const sy0 = (from.a * from.d - from.b * from.c) / sx0;
    const sy1 = (to.a * to.d - to.b * to.c) / sx1;
    const rot0 = std.math.atan2(from.b, from.a);
    const rot1 = std.math.atan2(to.b, to.a);
    var delta = rot1 - rot0;
    if (delta > std.math.pi) delta -= 2 * std.math.pi;
    if (delta < -std.math.pi) delta += 2 * std.math.pi;
    const shear0 = (from.a * from.c + from.b * from.d) / (sx0 * sx0);
    const shear1 = (to.a * to.c + to.b * to.d) / (sx1 * sx1);
    return Matrix2D.makeTranslate(interpolateNumber(from.tx, to.tx, progress), interpolateNumber(from.ty, to.ty, progress)).multiply(Matrix2D.makeRotate(rot0 + delta * progress)).multiply(.{ .c = interpolateNumber(shear0, shear1, progress) }).multiply(Matrix2D.makeScale(interpolateNumber(sx0, sx1, progress), interpolateNumber(sy0, sy1, progress)));
}

/// Evaluates transition progress given duration, delay, timing curve, and elapsed time (in seconds).
pub fn evaluateTransitionProgress(duration: f32, delay: f32, curve: CubicBezier, elapsed: f32) f32 {
    if (duration <= 0.0) return 1.0;
    if (elapsed < delay) return 0.0;
    const time_in_trans = elapsed - delay;
    if (time_in_trans >= duration) return 1.0;
    const linear_p = time_in_trans / duration;
    return curve.solve(linear_p);
}

const geometry = @import("geometry.zig");
pub const BasicShape = geometry.BasicShape;

pub fn interpolateBasicShape(from: BasicShape, to: BasicShape, progress: f32) ?BasicShape {
    switch (from) {
        .circle => |c0| switch (to) {
            .circle => |c1| return .{
                .circle = .{
                    .cx = interpolateNumber(c0.cx, c1.cx, progress),
                    .cy = interpolateNumber(c0.cy, c1.cy, progress),
                    .r = interpolateNumber(c0.r, c1.r, progress),
                },
            },
            else => return null,
        },
        .ellipse => |e0| switch (to) {
            .ellipse => |e1| return .{
                .ellipse = .{
                    .cx = interpolateNumber(e0.cx, e1.cx, progress),
                    .cy = interpolateNumber(e0.cy, e1.cy, progress),
                    .rx = interpolateNumber(e0.rx, e1.rx, progress),
                    .ry = interpolateNumber(e0.ry, e1.ry, progress),
                },
            },
            else => return null,
        },
        .inset => |inset_from| switch (to) {
            .inset => |inset_to| {
                var r: [4]f32 = undefined;
                for (0..4) |idx| {
                    r[idx] = interpolateNumber(inset_from.radii[idx], inset_to.radii[idx], progress);
                }
                return .{
                    .inset = .{
                        .top = interpolateNumber(inset_from.top, inset_to.top, progress),
                        .right = interpolateNumber(inset_from.right, inset_to.right, progress),
                        .bottom = interpolateNumber(inset_from.bottom, inset_to.bottom, progress),
                        .left = interpolateNumber(inset_from.left, inset_to.left, progress),
                        .radii = r,
                    },
                };
            },
            else => return null,
        },
        .polygon => |p0| switch (to) {
            .polygon => |p1| {
                if (p0.points.len != p1.points.len) return null;
                return to;
            },
            else => return null,
        },
    }
}
