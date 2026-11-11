//! Small balanced-token scanner shared by CSS value consumers.
const std = @import("std");
pub const Tokens = struct {
    input: []const u8,
    separators: []const u8,
    pos: usize = 0,
    pub fn next(self: *Tokens) ?[]const u8 {
        while (self.pos < self.input.len and std.mem.indexOfScalar(u8, self.separators, self.input[self.pos]) != null) self.pos += 1;
        if (self.pos == self.input.len) return null;
        const start = self.pos;
        var depth: usize = 0;
        var quote: u8 = 0;
        while (self.pos < self.input.len) : (self.pos += 1) {
            const c = self.input[self.pos];
            if (quote != 0) {
                if (c == quote) quote = 0;
            } else if (c == '\'' or c == '"') {
                quote = c;
            } else if (c == '(' or c == '[') {
                depth += 1;
            } else if (c == ')' or c == ']') {
                if (depth > 0) depth -= 1;
            } else if (depth == 0 and std.mem.indexOfScalar(u8, self.separators, c) != null) break;
        }
        return std.mem.trim(u8, self.input[start..self.pos], " \t\r\n");
    }
};
