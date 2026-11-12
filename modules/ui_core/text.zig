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

/// Absolute CSS size ladder uses the host's established medium; relative sizes
/// use the parent's computed size rather than the root size.
pub fn fontSizeKeyword(raw: []const u8, parent: f32) ?f32 {
    const css = std.mem.trim(u8, raw, " \t\r\n");
    inline for (.{ "xx-small", "x-small", "small", "medium", "large", "x-large", "xx-large", "xxx-large" }, .{ 0.6, 0.75, 0.889, 1.0, 1.2, 1.5, 2.0, 3.0 }) |name, ratio| {
        if (std.ascii.eqlIgnoreCase(css, name)) return default_font_size * ratio;
    }
    if (std.ascii.eqlIgnoreCase(css, "smaller")) return parent / 1.2;
    if (std.ascii.eqlIgnoreCase(css, "larger")) return parent * 1.2;
    return null;
}

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
/// Immutable, per-run styling shared by measurement, rasterization and hit testing.
pub const Typography = struct {
    font_family: []const u8 = "system-ui",
    font_feature_settings: []const u8 = "normal",
    font_weight: f32 = 400,
    font_style: []const u8 = "normal",
    language: []const u8 = "",
    text_transform: []const u8 = "none",
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    tab_size: f32 = 8,
    tab_size_is_length: bool = false,
    text_indent: f32 = 0,
};
pub const StyledMeasureFn = *const fn (?*anyopaque, []const u8, f32, Typography) Metrics;
pub const StyledPositionFn = *const fn (?*anyopaque, []const u8, f32, f32, Typography) usize;

pub const ShapedLine = struct {
    text: []const u8,
    width: f32,
    height: f32,
    ascent: f32,
    /// First-line indentation, relative to the line's content box.
    indent: f32 = 0,
    offset_x: f32 = 0,
};

pub const Wrap = struct {
    lines: usize = 0,
    widest: f32 = 0,
};

pub const Text = struct {
    ctx: ?*anyopaque = null,
    measure_fn: ?MeasureFn = null,
    position_fn: ?PositionFn = null,
    styled_measure_fn: ?StyledMeasureFn = null,
    styled_position_fn: ?StyledPositionFn = null,
    typography: Typography = .{},

    pub fn isMeasured(self: Text) bool {
        return self.measure_fn != null or self.styled_measure_fn != null;
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
        if (self.styled_measure_fn) |f| return f(self.ctx, content, px, self.typography);
        var metrics = if (self.measure_fn) |f| f(self.ctx, content, px) else estimate(content, px);
        // Preserve legacy callbacks while giving their fallback spacing semantics.
        var offset: usize = 0;
        var advance: f32 = 0;
        const edit = @import("text_edit.zig");
        const space = if (self.measure_fn) |f| f(self.ctx, " ", px).width else estimate(" ", px).width;
        while (offset < content.len) {
            const next = edit.nextGrapheme(content, offset);
            const cluster = content[offset..next];
            if (cluster.len == 1 and cluster[0] == '\t') {
                const stop = if (self.typography.tab_size_is_length) self.typography.tab_size else self.typography.tab_size * (space + self.typography.letter_spacing + self.typography.word_spacing);
                if (stop > 0) advance += stop - @mod(advance, stop);
            } else {
                advance += (if (self.measure_fn) |f| f(self.ctx, cluster, px).width else estimate(cluster, px).width) + self.typography.letter_spacing;
                if (std.mem.eql(u8, cluster, " ") or std.mem.eql(u8, cluster, "\xc2\xa0")) advance += self.typography.word_spacing;
            }
            offset = next;
        }
        if (self.typography.letter_spacing != 0 or self.typography.word_spacing != 0 or std.mem.indexOfScalar(u8, content, '\t') != null) {
            metrics.width = @max(0, advance);
        }
        return metrics;
    }

    pub fn position(self: Text, content: []const u8, x: f32, font_size: f32) ?usize {
        if (self.styled_position_fn) |f| return f(self.ctx, content, x, size(font_size), self.typography);
        if (self.position_fn) |f| return f(self.ctx, content, x, size(font_size));
        return null;
    }

    /// Returns an arena-owned ellipsized run; the authoring text is untouched.
    pub fn ellipsize(self: Text, a: std.mem.Allocator, content: []const u8, font_size: f32, available: f32) ![]const u8 {
        if (self.width(content, font_size) <= available) return content;
        const ellipsis = "\xe2\x80\xa6";
        if (self.width(ellipsis, font_size) > available) return "";
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(a);
        const edit = @import("text_edit.zig");
        var end: usize = 0;
        while (end < content.len) {
            const next = edit.nextGrapheme(content, end);
            result.clearRetainingCapacity();
            try result.appendSlice(a, content[0..next]);
            try result.appendSlice(a, ellipsis);
            if (self.width(result.items, font_size) > available) break;
            end = next;
        }
        result.clearRetainingCapacity();
        try result.appendSlice(a, content[0..end]);
        try result.appendSlice(a, ellipsis);
        return result.toOwnedSlice(a);
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
        var first = true;
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |raw_line| {
            const line = trimCarriageReturn(raw_line);
            const w = self.width(line, font_size) + if (first) self.typography.text_indent else @as(f32, 0);
            first = false;
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

    pub fn wrap(self: Text, content: []const u8, font_size: f32, available: f32) Wrap {
        return self.wrapWithWhitespace(content, font_size, available, "normal");
    }

    pub fn wrapWithWhitespace(self: Text, content: []const u8, font_size: f32, available: f32, white_space: []const u8) Wrap {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const lines = self.shapeLines(arena.allocator(), content, font_size, available, white_space) catch return .{ .lines = if (content.len == 0) 0 else 1, .widest = self.maxContentWidth(content, font_size) };
        var result = Wrap{ .lines = lines.len };
        for (lines) |line| result.widest = @max(result.widest, line.width + line.indent);
        return result;
    }
    /// Lines borrow author text. Only overflow presentation allocates new text.
    /// Measurements use complete candidate runs so shaping and tabs match paint.
    pub fn shapeLines(self: Text, allocator: std.mem.Allocator, content: []const u8, font_size: f32, available: f32, white_space: []const u8) ![]ShapedLine {
        var list: std.ArrayList(ShapedLine) = .empty;
        errdefer list.deinit(allocator);
        if (content.len == 0) return list.toOwnedSlice(allocator);
        const preserve = std.mem.eql(u8, white_space, "pre") or std.mem.eql(u8, white_space, "pre-wrap") or std.mem.eql(u8, white_space, "break-spaces");
        const no_wrap = std.mem.eql(u8, white_space, "nowrap") or std.mem.eql(u8, white_space, "pre") or available <= 0;
        const line_h = self.lineHeight(font_size);
        const asc = self.ascent(font_size);
        var hard_lines = std.mem.splitScalar(u8, content, '\n');
        while (hard_lines.next()) |raw| {
            const hard_line = trimCarriageReturn(raw);
            if (no_wrap or hard_line.len == 0) {
                try list.append(allocator, .{ .text = hard_line, .width = self.width(hard_line, font_size), .height = line_h, .ascent = asc, .indent = if (list.items.len == 0) self.typography.text_indent else 0 });
                continue;
            }
            var start: usize = 0;
            while (start < hard_line.len) {
                if (!preserve) while (start < hard_line.len and (hard_line[start] == ' ' or hard_line[start] == '\t')) : (start += 1) {};
                if (start == hard_line.len) break;
                const indent: f32 = if (list.items.len == 0) self.typography.text_indent else 0;
                const capacity = @max(0, available - indent);
                var end = start;
                var accepted = start;
                while (end < hard_line.len) {
                    // A break opportunity follows each whitespace sequence.
                    while (end < hard_line.len and hard_line[end] != ' ' and hard_line[end] != '\t') : (end += 1) {}
                    const word_end = end;
                    while (end < hard_line.len and (hard_line[end] == ' ' or hard_line[end] == '\t')) : (end += 1) {}
                    const candidate_end = if (preserve) end else word_end;
                    if (accepted > start and self.width(hard_line[start..candidate_end], font_size) > capacity) break;
                    accepted = candidate_end;
                    if (self.width(hard_line[start..candidate_end], font_size) > capacity) break;
                }
                if (accepted == start) accepted = end;
                const slice = hard_line[start..accepted];
                try list.append(allocator, .{ .text = slice, .width = self.width(slice, font_size), .height = line_h, .ascent = asc, .indent = indent });
                start = accepted;
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
