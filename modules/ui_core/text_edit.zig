//! UTF-8 byte-indexed single-line editing state; allocation belongs to the host.
const std = @import("std");

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

    pub fn left(self: *TextEdit, value: []const u8, extend: bool) void {
        self.clamp(value);
        const selected = self.selection();
        if (!extend and selected.start != selected.end) {
            self.move(selected.start, false);
            return;
        }
        var offset = self.cursor;
        if (offset > 0) {
            offset -= 1;
            while (offset > 0 and value[offset] & 0xc0 == 0x80) offset -= 1;
        }
        self.move(offset, extend);
    }

    pub fn right(self: *TextEdit, value: []const u8, extend: bool) void {
        self.clamp(value);
        const selected = self.selection();
        if (!extend and selected.start != selected.end) {
            self.move(selected.end, false);
            return;
        }
        var offset = self.cursor;
        if (offset < value.len) {
            offset += 1;
            while (offset < value.len and value[offset] & 0xc0 == 0x80) offset += 1;
        }
        self.move(offset, extend);
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
