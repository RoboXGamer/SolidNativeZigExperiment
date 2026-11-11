//! Text measurement seam between layout and the rendering backend.
//!
//! `ui_core` never measures glyphs itself: the backend owns the font, so it
//! installs a `MeasureFn` and layout asks for widths, line heights and
//! ascents. The Raylib backend plugs in `MeasureText`, which makes intrinsic
//! sizing (min/max-content, flex-basis `content`, auto heights) use real font
//! metrics instead of a per-character guess.
//!
//! Without a measurer (headless layout tests, the Node tree probes) the same
//! API falls back to a metric estimate, so behaviour stays defined everywhere.
const std = @import("std");

pub const default_font_size: f32 = 20;

/// Average advance of the Raylib built-in font, in em fractions. Only used when
/// no backend measurer is installed.
pub const fallback_advance_ratio: f32 = 0.5;
pub const fallback_line_height_ratio: f32 = 1.2;
pub const fallback_ascent_ratio: f32 = 0.8;

/// Per-run text metrics, all in device pixels for the requested font size.
pub const Metrics = struct {
    width: f32 = 0,
    /// Line box height, i.e. what one line of this run occupies vertically.
    height: f32 = 0,
    /// Baseline offset from the top of the line box.
    ascent: f32 = 0,
};

/// `ctx` is backend-owned state (a font handle, a cache, ...). It is opaque so
/// `ui_core` keeps no dependency on the renderer.
pub const MeasureFn = *const fn (ctx: ?*anyopaque, content: []const u8, font_size: f32) Metrics;

pub const Text = struct {
    ctx: ?*anyopaque = null,
    measure_fn: ?MeasureFn = null,

    pub fn isMeasured(self: Text) bool {
        return self.measure_fn != null;
    }

    fn size(font_size: f32) f32 {
        return if (font_size > 0) font_size else default_font_size;
    }

    pub fn measure(self: Text, content: []const u8, font_size: f32) Metrics {
        const px = size(font_size);
        if (content.len == 0) return .{ .width = 0, .height = px * fallback_line_height_ratio, .ascent = px * fallback_ascent_ratio };
        if (self.measure_fn) |f| return f(self.ctx, content, px);
        return estimate(content, px);
    }

    pub fn width(self: Text, content: []const u8, font_size: f32) f32 {
        return self.measure(content, font_size).width;
    }

    /// Height of one line box, including leading.
    pub fn lineHeight(self: Text, font_size: f32) f32 {
        const px = size(font_size);
        const m = self.measure("\u{44}y", px);
        return if (m.height > 0) m.height else px * fallback_line_height_ratio;
    }

    pub fn ascent(self: Text, font_size: f32) f32 {
        const px = size(font_size);
        const m = self.measure("\u{44}y", px);
        return if (m.ascent > 0) m.ascent else px * fallback_ascent_ratio;
    }

    /// Widest line of an unwrapped run; `\n` starts a new line.
    pub fn maxContentWidth(self: Text, content: []const u8, font_size: f32) f32 {
        var widest: f32 = 0;
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            const w = self.width(line, font_size);
            if (w > widest) widest = w;
        }
        return widest;
    }

    /// Widest unbreakable word, i.e. the min-content width of the run.
    pub fn minContentWidth(self: Text, content: []const u8, font_size: f32) f32 {
        var widest: f32 = 0;
        var it = std.mem.tokenizeAny(u8, content, " \t\r\n");
        while (it.next()) |word| {
            const w = self.width(word, font_size);
            if (w > widest) widest = w;
        }
        return widest;
    }

    /// Greedy word wrap that reports how many lines the run needs and the
    /// widest actual line. Used by callers that want wrapping without a full
    /// inline formatting context.
    pub fn wrap(self: Text, content: []const u8, font_size: f32, available: f32) Wrap {
        const space = self.width(" ", font_size);
        var result = Wrap{ .lines = if (content.len == 0) 0 else 1, .widest = 0 };
        if (available <= 0) {
            result.widest = self.maxContentWidth(content, font_size);
            return result;
        }
        var line: f32 = 0;
        var words = std.mem.tokenizeAny(u8, content, " \t\r\n");
        var first = true;
        while (words.next()) |word| {
            const w = self.width(word, font_size);
            if (first) {
                line = w;
                first = false;
            } else if (line + space + w <= available) {
                line += space + w;
            } else {
                if (line > result.widest) result.widest = line;
                result.lines += 1;
                line = w;
            }
        }
        if (line > result.widest) result.widest = line;
        return result;
    }
};

pub const Wrap = struct { lines: usize = 0, widest: f32 = 0 };

pub fn estimate(content: []const u8, font_size: f32) Metrics {
    return .{
        .width = @as(f32, @floatFromInt(content.len)) * font_size * fallback_advance_ratio,
        .height = font_size * fallback_line_height_ratio,
        .ascent = font_size * fallback_ascent_ratio,
    };
}

/// Deterministic measurer for tests: every byte advances `advance` em at
/// `font_size`, with the line box equal to the font size.
pub fn fixedMeasurer(comptime advance: f32) MeasureFn {
    return struct {
        fn measure(_: ?*anyopaque, content: []const u8, font_size: f32) Metrics {
            const width = @as(f32, @floatFromInt(content.len)) * advance * font_size;
            return .{ .width = width, .height = font_size, .ascent = font_size * 0.8 };
        }
    }.measure;
}

test "estimate scales with length and font size" {
    const a = estimate("abcd", 10);
    const b = estimate("abcdefgh", 10);
    try std.testing.expectEqual(@as(f32, 20), a.width);
    try std.testing.expectEqual(@as(f32, 40), b.width);
    try std.testing.expectEqual(@as(f32, 12), a.height);
}

test "max-content measures the widest line and min-content the widest word" {
    const t = Text{};
    try std.testing.expectApproxEqAbs(@as(f32, 20), t.maxContentWidth("abcd\nab", 10), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20), t.minContentWidth("abcd ab", 10), 0.01);
}

test "backend measurer overrides the estimate" {
    const t = Text{ .measure_fn = fixedMeasurer(1.0) };
    // "abcd" * 1 em * 10px = 40px with the test measurer, 20px by estimate.
    try std.testing.expectEqual(@as(f32, 40), t.width("abcd", 10));
    try std.testing.expectEqual(@as(f32, 20), (Text{}).width("abcd", 10));
    try std.testing.expect(t.isMeasured());
    try std.testing.expect(!(Text{}).isMeasured());
}

test "wrap counts lines and reports the widest line" {
    const t = Text{ .measure_fn = fixedMeasurer(1.0) };
    const w = t.wrap("aaa bb ccccc", 10, 40);
    try std.testing.expectEqual(@as(usize, 3), w.lines);
    try std.testing.expectEqual(@as(f32, 50), w.widest);
}
