//! CSS Transitions and Animation timing curve solver and interpolators.
const std = @import("std");
const transform_mod = @import("transform.zig");
pub const Matrix2D = transform_mod.Matrix2D;

pub const CubicBezier = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,

    pub const linear: CubicBezier = .{ .x1 = 0.0, .y1 = 0.0, .x2 = 1.0, .y2 = 1.0 };
    pub const ease: CubicBezier = .{ .x1 = 0.25, .y1 = 0.1, .x2 = 0.25, .y2 = 1.0 };
    pub const ease_in: CubicBezier = .{ .x1 = 0.42, .y1 = 0.0, .x2 = 1.0, .y2 = 1.0 };
    pub const ease_out: CubicBezier = .{ .x1 = 0.0, .y1 = 0.0, .x2 = 0.58, .y2 = 1.0 };
    pub const ease_in_out: CubicBezier = .{ .x1 = 0.42, .y1 = 0.0, .x2 = 0.58, .y2 = 1.0 };

    fn sampleCurveX(self: CubicBezier, t: f32) f32 {
        // ((1 - 3*x2 + 3*x1)*t + (3*x2 - 6*x1))*t + 3*x1)*t
        const cx = 3.0 * self.x1;
        const bx = 3.0 * (self.x2 - self.x1) - cx;
        const ax = 1.0 - cx - bx;
        return ((ax * t + bx) * t + cx) * t;
    }

    fn sampleCurveY(self: CubicBezier, t: f32) f32 {
        const cy = 3.0 * self.y1;
        const by = 3.0 * (self.y2 - self.y1) - cy;
        const ay = 1.0 - cy - by;
        return ((ay * t + by) * t + cy) * t;
    }

    fn sampleCurveDerivativeX(self: CubicBezier, t: f32) f32 {
        const cx = 3.0 * self.x1;
        const bx = 3.0 * (self.x2 - self.x1) - cx;
        const ax = 1.0 - cx - bx;
        return (3.0 * ax * t + 2.0 * bx) * t + cx;
    }

    /// Solves for y given x (progress between 0.0 and 1.0) using Newton-Raphson with bisection fallback.
    pub fn solve(self: CubicBezier, x_in: f32) f32 {
        const x = std.math.clamp(x_in, 0.0, 1.0);
        if (x <= 0.0) return 0.0;
        if (x >= 1.0) return 1.0;

        // Try Newton-Raphson first
        var t = x;
        for (0..8) |_| {
            const current_x = self.sampleCurveX(t) - x;
            if (@abs(current_x) < 1e-5) return self.sampleCurveY(t);
            const d = self.sampleCurveDerivativeX(t);
            if (@abs(d) < 1e-6) break;
            t -= current_x / d;
        }

        // Bisection fallback
        var t0: f32 = 0.0;
        var t1: f32 = 1.0;
        t = x;

        while (t0 < t1) {
            const current_x = self.sampleCurveX(t);
            if (@abs(current_x - x) < 1e-5) return self.sampleCurveY(t);
            if (x > current_x) {
                t0 = t;
            } else {
                t1 = t;
            }
            t = (t1 + t0) * 0.5;
            if (t1 - t0 < 1e-5) break;
        }

        return self.sampleCurveY(t);
    }
};

pub fn parseTimingFunction(str_in: []const u8) CubicBezier {
    const str = std.mem.trim(u8, str_in, " \t\r\n");
    if (std.mem.eql(u8, str, "linear")) return CubicBezier.linear;
    if (std.mem.eql(u8, str, "ease")) return CubicBezier.ease;
    if (std.mem.eql(u8, str, "ease-in")) return CubicBezier.ease_in;
    if (std.mem.eql(u8, str, "ease-out")) return CubicBezier.ease_out;
    if (std.mem.eql(u8, str, "ease-in-out")) return CubicBezier.ease_in_out;

    if (std.mem.startsWith(u8, str, "cubic-bezier(") and std.mem.endsWith(u8, str, ")")) {
        const inner = str[13 .. str.len - 1];
        var it = std.mem.tokenizeAny(u8, inner, ", \t");
        const x1_str = it.next() orelse return CubicBezier.ease;
        const y1_str = it.next() orelse return CubicBezier.ease;
        const x2_str = it.next() orelse return CubicBezier.ease;
        const y2_str = it.next() orelse return CubicBezier.ease;

        const x1 = std.fmt.parseFloat(f32, std.mem.trim(u8, x1_str, " ")) catch 0.25;
        const y1 = std.fmt.parseFloat(f32, std.mem.trim(u8, y1_str, " ")) catch 0.1;
        const x2 = std.fmt.parseFloat(f32, std.mem.trim(u8, x2_str, " ")) catch 0.25;
        const y2 = std.fmt.parseFloat(f32, std.mem.trim(u8, y2_str, " ")) catch 1.0;

        return .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2 };
    }

    return CubicBezier.ease;
}

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
    const p = progress;
    return .{
        .a = from.a + (to.a - from.a) * p,
        .b = from.b + (to.b - from.b) * p,
        .c = from.c + (to.c - from.c) * p,
        .d = from.d + (to.d - from.d) * p,
        .tx = from.tx + (to.tx - from.tx) * p,
        .ty = from.ty + (to.ty - from.ty) * p,
    };
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
