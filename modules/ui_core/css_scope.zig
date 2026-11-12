//! CSS @scope at-rule evaluation and scoping rules (CSS Cascading and Inheritance Level 6).
//! Supports donut scoping (@scope (<start>) to (<end>)) and nested rules (& / :scope).
const std = @import("std");
const core = @import("root.zig");

pub const Ancestor = struct {
    id: u32,
    type: []const u8,
    classes: []const []const u8 = &.{},
};

pub const ScopeRule = struct {
    /// Selector matching the scoping root element. Null means implicit :scope root.
    scope_start: ?[]const u8 = null,
    /// Selector matching the scope boundary / limit (donut scope).
    scope_end: ?[]const u8 = null,
    /// Scoped selector pattern (e.g. "& .item", ":scope > div", "label").
    selector: []const u8,

    pub fn matchesElement(selector_str: []const u8, element_type: []const u8, classes: []const []const u8) bool {
        const s = std.mem.trim(u8, selector_str, " \t\r\n");
        if (s.len == 0 or std.mem.eql(u8, s, "*")) return true;
        if (std.mem.startsWith(u8, s, ".")) {
            const target_class = s[1..];
            for (classes) |c| {
                if (std.mem.eql(u8, c, target_class)) return true;
            }
            return false;
        }
        return std.ascii.eqlIgnoreCase(s, element_type);
    }

    /// Evaluates whether a target node is within the scoped tree defined by @scope.
    /// In a donut scope, the element must be a descendant of a node matching scope_start,
    /// and NO intervening ancestor may match scope_end.
    pub fn inScope(self: ScopeRule, ancestors: []const Ancestor) bool {
        var found_start = (self.scope_start == null);
        var start_index: usize = 0;

        if (self.scope_start) |start_sel| {
            var i: usize = ancestors.len;
            while (i > 0) {
                i -= 1;
                if (matchesElement(start_sel, ancestors[i].type, ancestors[i].classes)) {
                    found_start = true;
                    start_index = i;
                    break;
                }
            }
        }

        if (!found_start) return false;

        // Check if any ancestor between start_index and target matches scope_end
        if (self.scope_end) |end_sel| {
            for (ancestors[start_index..]) |anc| {
                if (matchesElement(end_sel, anc.type, anc.classes)) {
                    return false; // Excluded by donut scope boundary
                }
            }
        }

        return true;
    }

    /// Tests whether target element matches this scoped rule.
    pub fn matches(self: ScopeRule, target_type: []const u8, target_classes: []const []const u8, ancestors: []const Ancestor) bool {
        if (!self.inScope(ancestors)) return false;
        const s = std.mem.trim(u8, self.selector, " \t\r\n");
        if (std.mem.startsWith(u8, s, "&") or std.mem.startsWith(u8, s, ":scope")) {
            // Nested selector
            var rest = if (std.mem.startsWith(u8, s, "&")) s[1..] else s[6..];
            rest = std.mem.trim(u8, rest, " \t\r\n");
            if (rest.len == 0) return true;
            if (std.mem.startsWith(u8, rest, ">")) {
                rest = std.mem.trim(u8, rest[1..], " \t\r\n");
            }
            return matchesElement(rest, target_type, target_classes);
        }
        return matchesElement(s, target_type, target_classes);
    }
};
