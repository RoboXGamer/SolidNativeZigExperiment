//! CSS Media Queries Level 4 / 5 implementation.
//! Covers:
//! - overflow-block media feature (none, scroll, paged)
//! - overflow-inline media feature (none, scroll)
//! - Evaluation with boolean test, value test, and media query expressions
const std = @import("std");

pub const OverflowBlock = enum {
    none,
    scroll,
    paged,

    pub fn fromString(str: []const u8) ?OverflowBlock {
        const s = std.mem.trim(u8, str, " \t\r\n");
        if (std.ascii.eqlIgnoreCase(s, "none")) return .none;
        if (std.ascii.eqlIgnoreCase(s, "scroll")) return .scroll;
        if (std.ascii.eqlIgnoreCase(s, "paged")) return .paged;
        return null;
    }

    pub fn asString(self: OverflowBlock) []const u8 {
        return switch (self) {
            .none => "none",
            .scroll => "scroll",
            .paged => "paged",
        };
    }
};

pub const OverflowInline = enum {
    none,
    scroll,

    pub fn fromString(str: []const u8) ?OverflowInline {
        const s = std.mem.trim(u8, str, " \t\r\n");
        if (std.ascii.eqlIgnoreCase(s, "none")) return .none;
        if (std.ascii.eqlIgnoreCase(s, "scroll")) return .scroll;
        return null;
    }

    pub fn asString(self: OverflowInline) []const u8 {
        return switch (self) {
            .none => "none",
            .scroll => "scroll",
        };
    }
};

pub const MediaContext = struct {
    overflow_block: OverflowBlock = .scroll,
    overflow_inline: OverflowInline = .scroll,
    media_type: []const u8 = "screen",
    width: f32 = 800,
    height: f32 = 600,
};

/// Evaluates a media feature expression like `(overflow-block: scroll)` or `(overflow-inline)`
pub fn evaluateFeature(feature_expr: []const u8, ctx: MediaContext) bool {
    var s = std.mem.trim(u8, feature_expr, " \t\r\n()");
    if (s.len == 0) return true;

    if (std.mem.indexOfScalar(u8, s, ':')) |colon| {
        const name = std.mem.trim(u8, s[0..colon], " \t\r\n");
        const val = std.mem.trim(u8, s[colon + 1 ..], " \t\r\n");

        if (std.ascii.eqlIgnoreCase(name, "overflow-block")) {
            if (OverflowBlock.fromString(val)) |expected| {
                return ctx.overflow_block == expected;
            }
            return false;
        }

        if (std.ascii.eqlIgnoreCase(name, "overflow-inline")) {
            if (OverflowInline.fromString(val)) |expected| {
                return ctx.overflow_inline == expected;
            }
            return false;
        }

        if (std.ascii.eqlIgnoreCase(name, "width")) {
            // Basic length test
            const num = std.fmt.parseFloat(f32, val) catch return false;
            return ctx.width == num;
        }

        return false;
    } else {
        // Boolean context: true if feature is not 'none' and not 0
        if (std.ascii.eqlIgnoreCase(s, "overflow-block")) {
            return ctx.overflow_block != .none;
        }
        if (std.ascii.eqlIgnoreCase(s, "overflow-inline")) {
            return ctx.overflow_inline != .none;
        }
        return false;
    }
}

/// Evaluates a full media query string, e.g.:
/// `screen and (overflow-block: scroll)` or `(overflow-inline: none)`
pub fn evaluateMediaQuery(query: []const u8, ctx: MediaContext) bool {
    var s = std.mem.trim(u8, query, " \t\r\n");
    if (std.mem.startsWith(u8, s, "@media")) {
        s = std.mem.trim(u8, s[6..], " \t\r\n");
    }
    if (s.len == 0 or std.ascii.eqlIgnoreCase(s, "all")) return true;

    // Split by comma (logical OR)
    var comma_it = std.mem.splitScalar(u8, s, ',');
    while (comma_it.next()) |disjunction| {
        const branch = std.mem.trim(u8, disjunction, " \t\r\n");
        if (branch.len == 0) continue;

        var negated = false;
        var remaining = branch;
        if (std.mem.startsWith(u8, remaining, "not ") or std.mem.startsWith(u8, remaining, "not\t")) {
            negated = true;
            remaining = std.mem.trim(u8, remaining[4..], " \t\r\n");
        } else if (std.mem.startsWith(u8, remaining, "only ") or std.mem.startsWith(u8, remaining, "only\t")) {
            remaining = std.mem.trim(u8, remaining[5..], " \t\r\n");
        }

        var and_it = std.mem.tokenizeSequence(u8, remaining, " and ");
        var all_matched = true;

        while (and_it.next()) |token| {
            const trimmed_token = std.mem.trim(u8, token, " \t\r\n");
            if (trimmed_token.len == 0) continue;

            if (trimmed_token[0] == '(' and trimmed_token[trimmed_token.len - 1] == ')') {
                if (!evaluateFeature(trimmed_token, ctx)) {
                    all_matched = false;
                    break;
                }
            } else {
                // Media type (screen, print, all)
                if (std.ascii.eqlIgnoreCase(trimmed_token, "all")) {
                    // matches all
                } else if (!std.ascii.eqlIgnoreCase(trimmed_token, ctx.media_type)) {
                    all_matched = false;
                    break;
                }
            }
        }

        const result = if (negated) !all_matched else all_matched;
        if (result) return true;
    }

    return false;
}
