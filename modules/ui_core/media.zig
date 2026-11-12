//! Media query parsing and evaluation for responsive styles.
//! Implements @media (scripting: none | initial-only | enabled)
//! per CSS Media Queries 5.
const std = @import("std");

pub const Scripting = enum {
    none,
    initial_only,
    enabled,
};

pub const MediaEnvironment = struct {
    width: f32 = 800,
    height: f32 = 600,
    scripting: Scripting = .enabled,
    prefers_color_scheme: []const u8 = "dark",
    reduced_motion: bool = false,
};

pub const MediaFeatureOp = enum {
    none,
    equals,
    min,
    max,
};

pub fn evaluateScriptingFeature(val: []const u8, current: Scripting) bool {
    const trimmed = std.mem.trim(u8, val, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(trimmed, "enabled")) {
        return current == .enabled;
    } else if (std.ascii.eqlIgnoreCase(trimmed, "none")) {
        return current == .none;
    } else if (std.ascii.eqlIgnoreCase(trimmed, "initial-only")) {
        return current == .initial_only;
    }
    // Boolean context: (scripting) evaluates to true if scripting is NOT none
    if (trimmed.len == 0) {
        return current != .none;
    }
    return false;
}

/// Evaluates a media query string against the given environment.
/// Examples:
/// "(scripting: enabled)" -> true
/// "(scripting: none)" -> false
/// "not (scripting: none)" -> true
/// "(scripting)" -> true
pub fn evaluateMediaQuery(query_in: []const u8, env: MediaEnvironment) bool {
    var query = std.mem.trim(u8, query_in, " \t\r\n");
    if (std.ascii.startsWithIgnoreCase(query, "@media")) {
        query = std.mem.trim(u8, query["@media".len..], " \t\r\n");
    }

    var negated = false;
    if (std.ascii.startsWithIgnoreCase(query, "not ")) {
        negated = true;
        query = std.mem.trim(u8, query[4..], " \t\r\n");
    }

    // Strip outer parentheses if single group
    if (query.len >= 2 and query[0] == '(' and query[query.len - 1] == ')') {
        query = std.mem.trim(u8, query[1 .. query.len - 1], " \t\r\n");
    }

    // Check for "scripting" feature
    if (std.ascii.startsWithIgnoreCase(query, "scripting")) {
        var rest = std.mem.trim(u8, query["scripting".len..], " \t\r\n");
        if (rest.len > 0 and rest[0] == ':') {
            const val = std.mem.trim(u8, rest[1..], " \t\r\n");
            const result = evaluateScriptingFeature(val, env.scripting);
            return if (negated) !result else result;
        } else if (rest.len == 0) {
            // (scripting) boolean
            const result = evaluateScriptingFeature("", env.scripting);
            return if (negated) !result else result;
        }
    }

    // Unknown or unsupported feature returns false (or inverted if negated)
    return if (negated) true else false;
}
