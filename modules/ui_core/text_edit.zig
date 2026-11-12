//! UTF-8 byte-indexed single-line editing state; allocation belongs to the host.
const std = @import("std");
const text_mod = @import("text.zig");

const unicode = @import("unicode/graphemes.zig");
pub fn isCombining(cp: u21) bool {
    const p = unicode.property(cp);
    return p == .extend or p == .spacingmark or p == .zwj;
}
fn control(p: unicode.Property) bool {
    return p == .cr or p == .lf or p == .control;
}
fn codepoint(value: []const u8, offset: usize) struct { cp: u21, len: usize } {
    const len = std.unicode.utf8ByteSequenceLength(value[offset]) catch return .{ .cp = 0xfffd, .len = 1 };
    if (offset + len > value.len) return .{ .cp = 0xfffd, .len = 1 };
    return .{ .cp = std.unicode.utf8Decode(value[offset .. offset + len]) catch 0xfffd, .len = len };
}
/// Unicode 16.0 UAX #29 extended grapheme boundaries, including GB9c and GB11.
pub fn nextGrapheme(value: []const u8, from: usize) usize {
    if (from >= value.len) return value.len;
    const first = codepoint(value, from);
    var previous = unicode.property(first.cp);
    var end = from + first.len;
    var regional: usize = if (previous == .regional_indicator) 1 else 0;
    var pictographic = unicode.isPictographic(first.cp);
    var after_zwj = false;
    var consonant = unicode.conjunct(first.cp) == .consonant;
    var linker = false;
    while (end < value.len) {
        const c = codepoint(value, end);
        const prop = unicode.property(c.cp);
        const indic = unicode.conjunct(c.cp);
        const joins = if (previous == .cr and prop == .lf) true else if (control(previous) or control(prop)) false else if (previous == .l and (prop == .l or prop == .v or prop == .lv or prop == .lvt)) true else if ((previous == .lv or previous == .v) and (prop == .v or prop == .t)) true else if ((previous == .lvt or previous == .t) and prop == .t) true else if (prop == .extend or prop == .zwj or prop == .spacingmark or previous == .prepend) true else if (consonant and linker and indic == .consonant) true else if (after_zwj and unicode.isPictographic(c.cp)) true else if (previous == .regional_indicator and prop == .regional_indicator and regional % 2 == 1) true else false;
        if (!joins) break;
        after_zwj = prop == .zwj and pictographic;
        if (unicode.isPictographic(c.cp)) pictographic = true else if (prop != .extend) pictographic = false;
        if (indic == .consonant) {
            consonant = true;
            linker = false;
        } else if (indic == .linker) {
            linker = consonant or linker;
        } else if (indic != .extend) {
            consonant = false;
            linker = false;
        }
        if (prop == .regional_indicator) regional += 1 else regional = 0;
        previous = prop;
        end += c.len;
    }
    return end;
}
fn prevCodepoint(value: []const u8, idx: usize) usize {
    if (idx == 0) return 0;
    var i = @min(idx, value.len) - 1;
    while (i > 0 and value[i] & 0xc0 == 0x80) i -= 1;
    return i;
}
pub fn prevGrapheme(value: []const u8, from: usize) usize {
    var previous: usize = 0;
    var offset: usize = 0;
    while (offset < @min(from, value.len)) {
        previous = offset;
        offset = nextGrapheme(value, offset);
    }
    return previous;
}

pub fn positionForX(value: []const u8, click_x: f32, font_size: f32, t: text_mod.Text) usize {
    if (t.position(value, click_x, font_size)) |position| return @min(value.len, position);
    if (click_x <= 0) return 0;
    var offset: usize = 0;
    var prev_w: f32 = 0;
    while (offset < value.len) {
        const next = nextGrapheme(value, offset);
        const w = t.width(value[0..next], font_size);
        if (click_x < w) {
            if (click_x - prev_w < w - click_x) {
                return offset;
            } else {
                return next;
            }
        }
        prev_w = w;
        offset = next;
    }
    return value.len;
}

pub const TextEdit = struct {
    cursor: usize = 0,
    anchor: usize = 0,

    pub fn clamp(self: *TextEdit, value: []const u8) void {
        self.cursor = @min(self.cursor, value.len);
        self.anchor = @min(self.anchor, value.len);
        while (self.cursor > 0 and self.cursor < value.len and value[self.cursor] & 0xc0 == 0x80) self.cursor -= 1;
        while (self.anchor > 0 and self.anchor < value.len and value[self.anchor] & 0xc0 == 0x80) self.anchor -= 1;
    }

    pub fn selection(self: TextEdit) struct { start: usize, end: usize } {
        return .{ .start = @min(self.cursor, self.anchor), .end = @max(self.cursor, self.anchor) };
    }

    pub fn move(self: *TextEdit, offset: usize, extend: bool) void {
        self.cursor = offset;
        if (!extend) self.anchor = offset;
    }

    pub fn selectAll(self: *TextEdit, value: []const u8) void {
        self.anchor = 0;
        self.cursor = value.len;
    }

    pub fn selectWord(self: *TextEdit, value: []const u8, offset: usize) void {
        const off = @min(offset, value.len);
        var start = off;
        while (start > 0) {
            const prev = prevGrapheme(value, start);
            const slice = value[prev..start];
            if (slice.len == 1 and (slice[0] == ' ' or slice[0] == '\t' or slice[0] == '\n')) break;
            start = prev;
        }
        var end = off;
        while (end < value.len) {
            const next = nextGrapheme(value, end);
            const slice = value[end..next];
            if (slice.len == 1 and (slice[0] == ' ' or slice[0] == '\t' or slice[0] == '\n')) break;
            end = next;
        }
        self.anchor = start;
        self.cursor = end;
    }

    pub fn left(self: *TextEdit, value: []const u8, extend: bool) void {
        self.clamp(value);
        const selected = self.selection();
        if (!extend and selected.start != selected.end) {
            self.move(selected.start, false);
            return;
        }
        self.move(prevGrapheme(value, self.cursor), extend);
    }

    pub fn right(self: *TextEdit, value: []const u8, extend: bool) void {
        self.clamp(value);
        const selected = self.selection();
        if (!extend and selected.start != selected.end) {
            self.move(selected.end, false);
            return;
        }
        self.move(nextGrapheme(value, self.cursor), extend);
    }

    pub fn replace(self: *TextEdit, allocator: std.mem.Allocator, value: []const u8, inserted: []const u8) ![]const u8 {
        self.clamp(value);
        const selected = self.selection();
        const result = try allocator.alloc(u8, selected.start + inserted.len + value.len - selected.end);
        @memcpy(result[0..selected.start], value[0..selected.start]);
        @memcpy(result[selected.start..][0..inserted.len], inserted);
        @memcpy(result[selected.start + inserted.len ..], value[selected.end..]);
        self.move(selected.start + inserted.len, false);
        return result;
    }

    pub fn backspace(self: *TextEdit, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        self.clamp(value);
        if (self.cursor == self.anchor) self.left(value, true);
        return self.replace(allocator, value, "");
    }

    pub fn delete(self: *TextEdit, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        self.clamp(value);
        if (self.cursor == self.anchor) self.right(value, true);
        return self.replace(allocator, value, "");
    }
};
