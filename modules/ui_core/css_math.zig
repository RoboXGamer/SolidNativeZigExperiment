//! Scalar CSS Values math. Callers retain dimensions and unresolved host metrics.
const std = @import("std");

pub const RoundStrategy = enum { nearest, up, down, to_zero };

pub fn extremum(a: f32, b: f32, minimum: bool) f32 {
    if (std.math.isNan(a) or std.math.isNan(b)) return std.math.nan(f32);
    if (a == 0 and b == 0) {
        const negative = if (minimum) std.math.signbit(a) or std.math.signbit(b) else std.math.signbit(a) and std.math.signbit(b);
        return if (negative) -@as(f32, 0.0) else 0;
    }
    return if (minimum) @min(a, b) else @max(a, b);
}

pub fn round(a: f32, interval: f32, strategy: RoundStrategy) f32 {
    if (std.math.isNan(a) or std.math.isNan(interval) or interval == 0) return std.math.nan(f32);
    const b = @abs(interval);
    if (std.math.isInf(a)) return if (std.math.isInf(b)) std.math.nan(f32) else a;
    if (a == 0) return a;
    if (std.math.isInf(b)) return switch (strategy) {
        .nearest, .to_zero => std.math.copysign(@as(f32, 0), a),
        .up => if (a > 0) std.math.inf(f32) else -@as(f32, 0),
        .down => if (a < 0) -std.math.inf(f32) else 0,
    };
    // f64 keeps the neighboring multiples finite for finite f32 inputs.
    const value: f64 = a;
    const step: f64 = b;
    const remainder = @rem(value, step);
    if (remainder == 0) return a;
    const lower = if (a < 0) value - remainder - step else value - remainder;
    const upper = if (a < 0) value - remainder else value - remainder + step;
    const result = switch (strategy) {
        .nearest => if (value - lower < upper - value) lower else upper,
        .up => upper,
        .down => lower,
        .to_zero => if (a < 0) upper else lower,
    };
    if (result == 0) return if (a < 0) -@as(f32, 0) else 0;
    return @floatCast(result);
}

pub fn remainder(a: f32, b: f32, modulus: bool) f32 {
    if (std.math.isNan(a) or std.math.isNan(b) or b == 0 or std.math.isInf(a)) return std.math.nan(f32);
    if (std.math.isInf(b)) {
        if (modulus and std.math.signbit(a) != std.math.signbit(b)) return std.math.nan(f32);
        return a;
    }
    var value = @rem(a, b);
    if (modulus) {
        if (value != 0 and std.math.signbit(value) != std.math.signbit(b)) value += b;
        if (value == 0) return std.math.copysign(@as(f32, 0), b);
    } else if (value == 0) return std.math.copysign(@as(f32, 0), a);
    return value;
}

pub fn power(a: f32, b: f32) f32 {
    // CSS propagates NaN even where the host pow has identity shortcuts.
    if (std.math.isNan(a) or std.math.isNan(b)) return std.math.nan(f32);
    if (@abs(a) == 1 and std.math.isInf(b)) return std.math.nan(f32);
    return std.math.pow(f32, a, b);
}

pub fn logarithm(a: f32, base: f32) f32 {
    if (std.math.isNan(a) or std.math.isNan(base) or a < 0 or base < 0 or base == 1) return std.math.nan(f32);
    const result = @log(a) / @log(base);
    return if (result == 0) 0 else result;
}

pub const Trig = enum { sin, cos, tan, asin, acos, atan };

pub fn trig(value: f32, degrees: bool, operation: Trig) f32 {
    if (std.math.isNan(value)) return value;
    const radians_per_degree: f64 = std.math.pi / 180.0;
    switch (operation) {
        .sin, .cos, .tan => {
            if (std.math.isInf(value)) return std.math.nan(f32);
            if (value == 0 and operation != .cos) return value;
            var angle: f64 = value;
            // Exact quarter-turns avoid manufacturing tiny nonzero values.
            if (degrees) {
                const reduced = @rem(value, @as(f32, 360));
                angle = reduced;
                if (operation == .sin and @rem(reduced, @as(f32, 180)) == 0) return 0;
                if (operation == .cos and (@abs(reduced) == 90 or @abs(reduced) == 270)) return 0;
                if (operation == .tan) {
                    if (reduced == 90 or reduced == -270) return std.math.inf(f32);
                    if (reduced == -90 or reduced == 270) return -std.math.inf(f32);
                    if (@rem(reduced, @as(f32, 180)) == 0) return 0;
                }
            }
            const radians = angle * (if (degrees) radians_per_degree else @as(f64, 1));
            return @floatCast(switch (operation) {
                .sin => @sin(radians),
                .cos => @cos(radians),
                .tan => @tan(radians),
                else => unreachable,
            });
        },
        .asin, .acos => {
            if (@abs(value) > 1) return std.math.nan(f32);
            const radians = if (operation == .asin) std.math.asin(@as(f64, value)) else std.math.acos(@as(f64, value));
            return @floatCast(radians / radians_per_degree);
        },
        .atan => return @floatCast(std.math.atan(@as(f64, value)) / radians_per_degree),
    }
}

pub fn atan2(y: f32, x: f32) f32 {
    if (std.math.isNan(y) or std.math.isNan(x)) return std.math.nan(f32);
    return @floatCast(std.math.atan2(@as(f64, y), @as(f64, x)) * (180.0 / std.math.pi));
}
