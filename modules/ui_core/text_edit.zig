//! UTF-8 byte-indexed single-line editing state; allocation belongs to the host.
const std = @import("std");
const text_mod = @import("text.zig");

pub fn isCombining(cp: u21) bool {
    return (cp >= 0x0300 and cp <= 0x036F) or
        (cp >= 0x1DC0 and cp <= 0x1DFF) or
        (cp >= 0x20D0 and cp <= 0x20FF) or
        (cp >= 0xFE00 and cp <= 0xFE0F) or
        (cp >= 0xFE20 and cp <= 0xFE2F) or
        (cp == 0x200D);
}

pub fn nextGrapheme(value: []const u8, from: usize) usize {
    if (from >= value.len) return value.len;
    var it = std.unicode.Utf8View.init(value[from..]) catch return from + 1;
    var iter = it.iterator();
    var end = from;
    if (iter.nextCodepointSlice()) |slice| {
        end += slice.len;
        while (iter.nextCodepoint()) |cp| {
            if (isCombining(cp)) {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch break;
                end += len;
            } else {
                break;
            }
        }
    }
    return end;
}

fn prevCodepoint(value: []const u8, idx: usize) usize {
    if (idx == 0) return 0;
    var i = idx - 1;
    while (i > 0 and (value[i] & 0xc0) == 0x80) i -= 1;
    return i;
}

pub fn prevGrapheme(value: []const u8, from: usize) usize {
    if (from == 0) return 0;
    var cur = prevCodepoint(value, from);
    while (cur > 0) {
        const cp_len = std.unicode.utf8ByteSequenceLength(value[cur]) catch 1;
        const cp_end = @min(value.len, cur + cp_len);
        if (std.unicode.utf8Decode(value[cur..cp_end])) |cp| {
            if (isCombining(cp)) {
                cur = prevCodepoint(value, cur);
                continue;
            }
        } else |_| {}
        break;
    }
    return cur;
}

pub fn positionForX(value: []const u8, click_x: f32, font_size: f32, t: text_mod.Text) usize {
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
