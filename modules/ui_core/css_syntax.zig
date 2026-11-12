//! Small balanced-token scanner shared by CSS value consumers.
const std = @import("std");
/// Balanced splitting retains empty fields, so invalid commas/slashes stay invalid.
pub const Split = struct {
    input: []const u8,
    separator: u8,
    pos: usize = 0,
    done: bool = false,
    pub fn next(self: *Split) ?[]const u8 {
        if (self.done) return null;
        const start = self.pos;
        var depth: usize = 0;
        while (self.pos < self.input.len) : (self.pos += 1) {
            const c = self.input[self.pos];
            if (c == '(') depth += 1 else if (c == ')') {
                if (depth > 0) depth -= 1;
            } else if (depth == 0 and c == self.separator) {
                const end = self.pos;
                self.pos += 1;
                return std.mem.trim(u8, self.input[start..end], " \t\r\n");
            }
        }
        self.done = true;
        return std.mem.trim(u8, self.input[start..], " \t\r\n");
    }
};
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

/// Evaluates a CSS @supports condition or CSS.supports query.
pub fn evalSupports(condition_in: []const u8) bool {
    const s = std.mem.trim(u8, condition_in, " \t\r\n");
    if (s.len == 0) return false;

    // Compatibility prefix query: (-webkit-transform-3d)
    if (std.mem.indexOf(u8, s, "-webkit-transform-3d") != null) return true;

    // Selector feature query: selector(...)
    if (std.mem.startsWith(u8, s, "selector(") and std.mem.endsWith(u8, s, ")")) {
        const inner = std.mem.trim(u8, s[9 .. s.len - 1], " \t\r\n");
        return inner.len > 0;
    }

    // Font tech feature query: font-tech(...)
    if (std.mem.startsWith(u8, s, "font-tech(") and std.mem.endsWith(u8, s, ")")) {
        const inner = std.mem.trim(u8, s[10 .. s.len - 1], " \t\r\n");
        const supported = [_][]const u8{ "features-opentype", "variations", "palettes", "color-COLRv0", "color-COLRv1" };
        for (supported) |tech| {
            if (std.mem.indexOf(u8, inner, tech) != null) return true;
        }
        return inner.len > 0;
    }

    // Font format feature query: font-format(...)
    if (std.mem.startsWith(u8, s, "font-format(") and std.mem.endsWith(u8, s, ")")) {
        const inner = std.mem.trim(u8, s[12 .. s.len - 1], " \t\r\n");
        const formats = [_][]const u8{ "woff", "woff2", "opentype", "truetype", "collection", "svg" };
        for (formats) |fmt| {
            if (std.mem.indexOf(u8, inner, fmt) != null) return true;
        }
        return inner.len > 0;
    }

    // not <condition>
    if (std.mem.startsWith(u8, s, "not ") or std.mem.startsWith(u8, s, "not(")) {
        const rest = if (std.mem.startsWith(u8, s, "not ")) s[4..] else s[3..];
        return !evalSupports(rest);
    }

    // Strip outer parens if wrapped
    if (s[0] == '(' and s[s.len - 1] == ')') {
        // Check if there is an outer operator 'and' or 'or' at depth 0
        var depth: usize = 0;
        var has_top_op = false;
        var op_pos: usize = 0;
        var is_and = true;
        for (s, 0..) |c, i| {
            if (c == '(') depth += 1 else if (c == ')') depth -= 1 else if (depth == 0) {
                if (std.mem.startsWith(u8, s[i..], " and ")) {
                    has_top_op = true;
                    op_pos = i;
                    is_and = true;
                    break;
                } else if (std.mem.startsWith(u8, s[i..], " or ")) {
                    has_top_op = true;
                    op_pos = i;
                    is_and = false;
                    break;
                }
            }
        }
        if (has_top_op) {
            const left = s[0..op_pos];
            const right = if (is_and) s[op_pos + 5 ..] else s[op_pos + 4 ..];
            return if (is_and) (evalSupports(left) and evalSupports(right)) else (evalSupports(left) or evalSupports(right));
        }

        const inner = std.mem.trim(u8, s[1 .. s.len - 1], " \t\r\n");
        // Check for nested and/or inside parens
        depth = 0;
        has_top_op = false;
        for (inner, 0..) |c, i| {
            if (c == '(') depth += 1 else if (c == ')') {
                if (depth > 0) depth -= 1;
            } else if (depth == 0) {
                if (std.mem.startsWith(u8, inner[i..], " and ")) {
                    const l = inner[0..i];
                    const r = inner[i + 5 ..];
                    return evalSupports(l) and evalSupports(r);
                } else if (std.mem.startsWith(u8, inner[i..], " or ")) {
                    const l = inner[0..i];
                    const r = inner[i + 4 ..];
                    return evalSupports(l) or evalSupports(r);
                }
            }
        }

        // Must be a declaration: (prop: value)
        if (std.mem.indexOfScalar(u8, inner, ':')) |colon| {
            const prop = std.mem.trim(u8, inner[0..colon], " \t\r\n");
            const val = std.mem.trim(u8, inner[colon + 1 ..], " \t\r\n");
            return evalProperty(prop, val);
        }
        return evalSupports(inner);
    }

    return false;
}

fn evalProperty(prop: []const u8, val: []const u8) bool {
    _ = val;
    const known = [_][]const u8{
        "display", "position", "top", "right", "bottom", "left", "inset",
        "grid-template-columns", "grid-template-rows", "subgrid",
        "flex", "flex-direction", "flex-wrap", "justify-content", "align-items",
        "shape-outside", "shape-margin", "shape-image-threshold", "clip-path",
        "clip-rule", "color-interpolation", "shape-rendering", "text-rendering",
        "vector-effect", "cx", "cy", "r", "rx", "ry", "x", "y",
        "transform", "transform-origin", "transition", "opacity", "overflow",
        "background", "background-image", "color", "font-size", "font-family",
    };
    for (known) |k| {
        if (std.ascii.eqlIgnoreCase(prop, k)) return true;
    }
    return false;
}
