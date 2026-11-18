const std = @import("std");

// Stay inside JS's exact integer range, including nanosecond arithmetic (~104 days).
pub const horizon: u64 = 9_007_199_254_740_991;
pub const epoch_ms: f64 = 1_700_000_000_000;
pub const Mode = enum { live, controlled };
pub fn fromMs(ms: f64) !u64 {
    if (!std.math.isFinite(ms) or ms < 0 or ms > @as(f64, @floatFromInt(horizon)) / 1e6) return error.ClockOutOfRange;
    return @intFromFloat(@ceil(ms * 1e6));
}
pub fn add(a: u64, b: u64) !u64 {
    if (a > horizon or b > horizon - a) return error.ClockOutOfRange;
    return a + b;
}
pub fn milliseconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e6;
}
pub fn seconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e9;
}
pub fn nextFrame(ns: u64) !u64 {
    const index = ns * 60 / 1_000_000_000 + 1;
    const at = (index * 1_000_000_000 + 59) / 60;
    if (at > horizon) return error.ClockOutOfRange;
    return at;
}
pub const Clock = struct {
    mode: Mode,
    origin: u64,
    now: u64 = 0,
    pub fn sample(self: *Clock, real_ns: u64) !void {
        if (self.mode == .live) self.now = @max(self.now, @min(horizon, real_ns -| self.origin));
    }
    pub fn reach(self: *Clock, ns: u64) !void {
        if (ns < self.now or ns > horizon) return error.ClockOutOfRange;
        self.now = ns;
    }
};

test "clock validation and rational frame cadence" {
    try std.testing.expectError(error.ClockOutOfRange, fromMs(std.math.nan(f64)));
    try std.testing.expectError(error.ClockOutOfRange, fromMs(-1));
    try std.testing.expectError(error.ClockOutOfRange, add(horizon, 1));
    var t: u64 = 0;
    for (0..60) |_| t = try nextFrame(t);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), t);
}
