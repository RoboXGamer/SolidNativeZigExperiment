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

/// CSS collapsing for the scene projection. The authoring tree keeps its text.
pub fn collapseWhitespace(a: std.mem.Allocator, input: []const u8) ![]const u8 {
    const result = try a.alloc(u8, input.len);
    var length: usize = 0;
    var pending = false;
    for (input) |c| {
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == 0x0c) {
            pending = length > 0;
            continue;
        }
        if (pending) {
            result[length] = ' ';
            length += 1;
            pending = false;
        }
        result[length] = c;
        length += 1;
    }
    if (std.mem.eql(u8, input, result[0..length])) {
        a.free(result);
        return input;
    }
    return result[0..length];
}

pub const default_font_size: f32 = 20;

/// Average advance of the Raylib built-in font, in em fractions. Only used when
/// no backend measurer is installed.
pub const fallback_advance_ratio: f32 = 0.5;
pub const fallback_line_height_ratio: f32 = 1.2;
pub const fallback_ascent_ratio: f32 = 0.8;
pub const fallback_descent_ratio: f32 = 0.2;

/// Per-run text metrics, all in device pixels for the requested font size.
pub const Metrics = struct {
    width: f32 = 0,
    /// Line box height, i.e. what one line of this run occupies vertically.
    height: f32 = 0,
    /// Baseline offset from the top of the line box.
    ascent: f32 = 0,
    /// Distance from the baseline to the bottom of the line box.
    descent: f32 = 0,
    /// Line leading (line height minus ascent + descent).
    leading: f32 = 0,
};

/// `ctx` is backend-owned state (a font handle, a cache, ...). It is opaque so
/// `ui_core` keeps no dependency on the renderer.
pub const MeasureFn = *const fn (ctx: ?*anyopaque, content: []const u8, font_size: f32) Metrics;
pub const PositionFn = *const fn (?*anyopaque, []const u8, f32, f32) usize;

pub const ShapedLine = struct {
    text: []const u8,
    width: f32,
    height: f32,
    ascent: f32,
};

pub const Wrap = struct {
    lines: usize = 0,
    widest: f32 = 0,
};

pub const Text = struct {
    ctx: ?*anyopaque = null,
    measure_fn: ?MeasureFn = null,
    position_fn: ?PositionFn = null,

    pub fn isMeasured(self: Text) bool {
        return self.measure_fn != null;
    }

    fn size(font_size: f32) f32 {
        return if (font_size > 0) font_size else default_font_size;
    }

    pub fn measure(self: Text, content: []const u8, font_size: f32) Metrics {
        const px = size(font_size);
        if (content.len == 0) {
            const h = px * fallback_line_height_ratio;
            const asc = px * fallback_ascent_ratio;
            const desc = px * fallback_descent_ratio;
            return .{ .width = 0, .height = h, .ascent = asc, .descent = desc, .leading = @max(0, h - (asc + desc)) };
        }
        if (self.measure_fn) |f| return f(self.ctx, content, px);
        return estimate(content, px);
    }

    pub fn width(self: Text, content: []const u8, font_size: f32) f32 {
        return self.measure(content, font_size).width;
    }

    /// Height of one line box, including leading.
    pub fn lineHeight(self: Text, font_size: f32) f32 {
        const px = size(font_size);
        const m = self.measure("Dy", px);
        return if (m.height > 0) m.height else px * fallback_line_height_ratio;
    }

    pub fn ascent(self: Text, font_size: f32) f32 {
        const px = size(font_size);
        const m = self.measure("Dy", px);
        return if (m.ascent > 0) m.ascent else px * fallback_ascent_ratio;
    }

    pub fn descent(self: Text, font_size: f32) f32 {
        const px = size(font_size);
        const m = self.measure("Dy", px);
        return if (m.descent > 0) m.descent else px * fallback_descent_ratio;
    }

    pub fn leading(self: Text, font_size: f32) f32 {
        const px = size(font_size);
        const m = self.measure("Dy", px);
        return if (m.leading > 0) m.leading else @max(0, self.lineHeight(px) - (self.ascent(px) + self.descent(px)));
    }

    fn trimCarriageReturn(s: []const u8) []const u8 {
        return if (s.len > 0 and s[s.len - 1] == '\r') s[0 .. s.len - 1] else s;
    }

    /// Widest line of an unwrapped run; `\n` starts a new line.
    pub fn maxContentWidth(self: Text, content: []const u8, font_size: f32) f32 {
        var widest: f32 = 0;
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |raw_line| {
            const line = trimCarriageReturn(raw_line);
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
        if (content.len == 0) return .{ .lines = 0, .widest = 0 };
        if (available <= 0) {
            const w = self.maxContentWidth(content, font_size);
            var lines: usize = 1;
            for (content) |c| if (c == '\n') {
                lines += 1;
            };
            return .{ .lines = lines, .widest = w };
        }
        const space = self.width(" ", font_size);
        var result = Wrap{ .lines = 0, .widest = 0 };
        var hard_lines = std.mem.splitScalar(u8, content, '\n');
        while (hard_lines.next()) |raw_line| {
            const hard_line = trimCarriageReturn(raw_line);
            var words = std.mem.tokenizeAny(u8, hard_line, " \t");
            var line: f32 = 0;
            var first = true;
            var line_had_word = false;
            while (words.next()) |word| {
                line_had_word = true;
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
            if (line_had_word or hard_line.len == 0) result.lines += 1;
        }
        if (result.lines == 0) result.lines = 1;
        return result;
    }

    /// Breaks text into shaped lines with computed coordinates and dimensions.
    pub fn shapeLines(
        self: Text,
        allocator: std.mem.Allocator,
        content: []const u8,
        font_size: f32,
        available: f32,
        white_space: []const u8,
    ) ![]ShapedLine {
        if (content.len == 0) return try allocator.alloc(ShapedLine, 0);
        const line_h = self.lineHeight(font_size);
        const asc = self.ascent(font_size);
        const is_nowrap = std.mem.eql(u8, white_space, "nowrap");

        var list: std.ArrayList(ShapedLine) = .empty;
        errdefer list.deinit(allocator);

        if (is_nowrap or available <= 0) {
            var it = std.mem.splitScalar(u8, content, '\n');
            while (it.next()) |raw_line| {
                const line = trimCarriageReturn(raw_line);
                const w = self.width(line, font_size);
                try list.append(allocator, .{
                    .text = line,
                    .width = w,
                    .height = line_h,
                    .ascent = asc,
                });
                if (is_nowrap) break;
            }
            return list.toOwnedSlice(allocator);
        }

        const space_w = self.width(" ", font_size);
        var hard_lines = std.mem.splitScalar(u8, content, '\n');
        while (hard_lines.next()) |raw_line| {
            const hard_line = trimCarriageReturn(raw_line);
            if (hard_line.len == 0) {
                try list.append(allocator, .{ .text = "", .width = 0, .height = line_h, .ascent = asc });
                continue;
            }

            var words = std.mem.tokenizeAny(u8, hard_line, " \t");
            var line_start: ?usize = null;
            var line_end: usize = 0;
            var line_w: f32 = 0;

            while (words.next()) |word| {
                const w = self.width(word, font_size);
                const word_start = @intFromPtr(word.ptr) - @intFromPtr(hard_line.ptr);
                const word_end = word_start + word.len;

                if (line_start == null) {
                    line_start = word_start;
                    line_end = word_end;
                    line_w = w;
                } else if (line_w + space_w + w <= available) {
                    line_end = word_end;
                    line_w += space_w + w;
                } else {
                    const slice = hard_line[line_start.?..line_end];
                    try list.append(allocator, .{
                        .text = slice,
                        .width = line_w,
                        .height = line_h,
                        .ascent = asc,
                    });
                    line_start = word_start;
                    line_end = word_end;
                    line_w = w;
                }
            }

            if (line_start) |start| {
                const slice = hard_line[start..line_end];
                try list.append(allocator, .{
                    .text = slice,
                    .width = line_w,
                    .height = line_h,
                    .ascent = asc,
                });
            }
        }

        return list.toOwnedSlice(allocator);
    }
};

pub fn estimate(content: []const u8, font_size: f32) Metrics {
    var count: usize = 0;
    if (std.unicode.Utf8View.init(content)) |view| {
        var it = view.iterator();
        while (it.nextCodepoint()) |_| count += 1;
    } else |_| {
        count = content.len;
    }
    const h = font_size * fallback_line_height_ratio;
    const asc = font_size * fallback_ascent_ratio;
    const desc = font_size * fallback_descent_ratio;
    const lead = @max(0, h - (asc + desc));
    return .{
        .width = @as(f32, @floatFromInt(count)) * font_size * fallback_advance_ratio,
        .height = h,
        .ascent = asc,
        .descent = desc,
        .leading = lead,
    };
}

/// Deterministic measurer for tests: every byte advances `advance` em at
/// `font_size`, with the line box equal to the font size.
pub fn fixedMeasurer(comptime advance: f32) MeasureFn {
    return struct {
        fn measure(_: ?*anyopaque, content: []const u8, font_size: f32) Metrics {
            var count: usize = 0;
            if (std.unicode.Utf8View.init(content)) |view| {
                var it = view.iterator();
                while (it.nextCodepoint()) |_| count += 1;
            } else |_| {
                count = content.len;
            }
            const width = @as(f32, @floatFromInt(count)) * advance * font_size;
            return .{
                .width = width,
                .height = font_size,
                .ascent = font_size * 0.8,
                .descent = font_size * 0.2,
                .leading = 0,
            };
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
