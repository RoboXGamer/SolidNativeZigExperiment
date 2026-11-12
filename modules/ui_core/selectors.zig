//! CSS Selectors Level 3 & Level 4 evaluation for Solid/Zig retained scene tree.
//!
//! Covers:
//! - :first-child, :last-child, :only-child (including no_parent_required)
//! - :nth-child(An+B), :nth-last-child(An+B)
//! - :nth-child(An+B of <selector>), :nth-last-child(An+B of <selector>)
//! - :first-of-type, :last-of-type, :only-of-type
//! - :nth-of-type(An+B), :nth-last-of-type(An+B)
//! - :not(<selector-list>)
//! - @namespace at-rule mapping and namespace-prefixed selectors (prefix|E, *|E, |E)
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;

pub const AnPlusB = struct {
    a: i32 = 0,
    b: i32 = 0,

    pub fn matches(self: AnPlusB, index: i32) bool {
        if (index <= 0) return false;
        if (self.a == 0) return index == self.b;
        const diff = index - self.b;
        if (@mod(diff, self.a) != 0) return false;
        return @divFloor(diff, self.a) >= 0;
    }

    pub fn parse(input: []const u8) ?AnPlusB {
        const s = std.mem.trim(u8, input, " \t\r\n");
        if (s.len == 0) return null;
        if (std.ascii.eqlIgnoreCase(s, "even")) return .{ .a = 2, .b = 0 };
        if (std.ascii.eqlIgnoreCase(s, "odd")) return .{ .a = 2, .b = 1 };

        // Pure integer, e.g. "3" or "-1"
        if (std.fmt.parseInt(i32, s, 10)) |val| {
            return .{ .a = 0, .b = val };
        } else |_| {}

        // An+B, e.g. "2n+1", "n", "-n+5", "+2n-3", "-2n"
        const n_idx = std.mem.indexOfScalar(u8, s, 'n') orelse std.mem.indexOfScalar(u8, s, 'N') orelse return null;
        const a_part = s[0..n_idx];
        var a: i32 = 1;
        if (a_part.len == 0 or std.mem.eql(u8, a_part, "+")) {
            a = 1;
        } else if (std.mem.eql(u8, a_part, "-")) {
            a = -1;
        } else {
            a = std.fmt.parseInt(i32, a_part, 10) catch return null;
        }

        var b: i32 = 0;
        const rest = std.mem.trim(u8, s[n_idx + 1 ..], " \t\r\n");
        if (rest.len > 0) {
            b = std.fmt.parseInt(i32, rest, 10) catch return null;
        }

        return .{ .a = a, .b = b };
    }
};

pub fn findIndex(node_id: u32, siblings: []const Node) ?usize {
    for (siblings, 0..) |s, i| {
        if (s.id == node_id) return i;
    }
    return null;
}

pub fn matchesFirstChild(node_id: u32, siblings: []const Node) bool {
    if (siblings.len == 0) return true; // no parent required
    return siblings[0].id == node_id;
}

pub fn matchesLastChild(node_id: u32, siblings: []const Node) bool {
    if (siblings.len == 0) return true;
    return siblings[siblings.len - 1].id == node_id;
}

pub fn matchesOnlyChild(node_id: u32, siblings: []const Node) bool {
    if (siblings.len <= 1) return true; // no parent required or single child
    return siblings.len == 1 and siblings[0].id == node_id;
}

pub fn matchesNthChild(node_id: u32, siblings: []const Node, rule: AnPlusB) bool {
    if (siblings.len == 0) return rule.matches(1);
    const idx = findIndex(node_id, siblings) orelse return false;
    return rule.matches(@intCast(idx + 1));
}

pub fn matchesNthLastChild(node_id: u32, siblings: []const Node, rule: AnPlusB) bool {
    if (siblings.len == 0) return rule.matches(1);
    const idx = findIndex(node_id, siblings) orelse return false;
    const rank: i32 = @intCast(siblings.len - idx);
    return rule.matches(rank);
}

pub fn matchesFirstOfType(node: *const Node, siblings: []const Node) bool {
    for (siblings) |s| {
        if (std.mem.eql(u8, s.type, node.type)) {
            return s.id == node.id;
        }
    }
    return true;
}

pub fn matchesLastOfType(node: *const Node, siblings: []const Node) bool {
    var i: usize = siblings.len;
    while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, siblings[i].type, node.type)) {
            return siblings[i].id == node.id;
        }
    }
    return true;
}

pub fn matchesOnlyOfType(node: *const Node, siblings: []const Node) bool {
    var count: usize = 0;
    for (siblings) |s| {
        if (std.mem.eql(u8, s.type, node.type)) count += 1;
    }
    return count <= 1;
}

pub fn matchesNthOfType(node: *const Node, siblings: []const Node, rule: AnPlusB) bool {
    var type_rank: i32 = 0;
    for (siblings) |s| {
        if (std.mem.eql(u8, s.type, node.type)) {
            type_rank += 1;
            if (s.id == node.id) return rule.matches(type_rank);
        }
    }
    return false;
}

pub fn matchesNthLastOfType(node: *const Node, siblings: []const Node, rule: AnPlusB) bool {
    var total_of_type: i32 = 0;
    var node_rank: i32 = 0;
    for (siblings) |s| {
        if (std.mem.eql(u8, s.type, node.type)) {
            total_of_type += 1;
            if (s.id == node.id) node_rank = total_of_type;
        }
    }
    if (node_rank == 0) return false;
    const rank_from_end = total_of_type - node_rank + 1;
    return rule.matches(rank_from_end);
}

pub const SelectorPredicate = *const fn (node: *const Node) bool;

pub fn matchesNthChildOf(node: *const Node, siblings: []const Node, rule: AnPlusB, is_last: bool, predicate: SelectorPredicate) bool {
    if (!predicate(node)) return false;
    var count: i32 = 0;
    var target_rank: i32 = 0;
    for (siblings) |*s| {
        if (predicate(s)) {
            count += 1;
            if (s.id == node.id) target_rank = count;
        }
    }
    if (target_rank == 0) return false;
    const rank = if (is_last) (count - target_rank + 1) else target_rank;
    return rule.matches(rank);
}

pub fn matchesNot(node: *const Node, predicates: []const SelectorPredicate) bool {
    for (predicates) |pred| {
        if (pred(node)) return false;
    }
    return true;
}

pub fn matchesNamespace(node_ns: ?[]const u8, prefix: []const u8, registered_url: ?[]const u8) bool {
    if (std.mem.eql(u8, prefix, "*")) {
        return true;
    }
    if (prefix.len == 0) {
        return node_ns == null or node_ns.?.len == 0;
    }
    if (registered_url) |url| {
        if (node_ns) |ns| {
            return std.mem.eql(u8, ns, url);
        }
    }
    return false;
}
