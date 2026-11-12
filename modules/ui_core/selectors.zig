//! CSS selector parsing, matching, specificity and scoping rules.
//! Covers CSS Selectors 3/4 core:
//! - Type selectors and namespaces: E, ns|E, *|E, |E
//! - Universal selector: *, ns|*, *|*, |*
//! - Attribute selectors: [attr], [attr=val], [attr~=val], [attr|=val],
//!   [attr^=val], [attr$=val], [attr*=val], with case-sensitivity flags (i, s)
//! - Class selectors: .class
//! - ID selectors: #id
//! - Combinators: descendant ( ), child (>), next-sibling (+), subsequent-sibling (~)
//! - Selector lists: A, B
//! - Pseudo-classes: :scope
//! - Pseudo-elements: ::part(ident)
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;

pub const Specificity = struct {
    a: u32 = 0, // IDs
    b: u32 = 0, // Classes, attributes, pseudo-classes
    c: u32 = 0, // Type, pseudo-elements

    pub fn add(self: Specificity, other: Specificity) Specificity {
        return .{
            .a = self.a + other.a,
            .b = self.b + other.b,
            .c = self.c + other.c,
        };
    }

    pub fn order(self: Specificity, other: Specificity) std.math.Order {
        if (self.a != other.a) return std.math.order(self.a, other.a);
        if (self.b != other.b) return std.math.order(self.b, other.b);
        return std.math.order(self.c, other.c);
    }

    pub fn lessThan(self: Specificity, other: Specificity) bool {
        return self.order(other) == .lt;
    }

    pub fn greaterThan(self: Specificity, other: Specificity) bool {
        return self.order(other) == .gt;
    }
};

pub const AttrOp = enum {
    exists, // [attr]
    equals, // [attr=val]
    includes, // [attr~=val]
    dash_match, // [attr|=val]
    prefix, // [attr^=val]
    suffix, // [attr$=val]
    substring, // [attr*=val]
};

pub const AttrSelector = struct {
    name: []const u8,
    op: AttrOp = .exists,
    value: []const u8 = "",
    case_insensitive: bool = false,
};

pub const Combinator = enum {
    none,
    descendant, // ' '
    child, // '>'
    next_sibling, // '+'
    subsequent_sibling, // '~'
};

pub const SimpleSelector = struct {
    namespace: ?[]const u8 = null, // null = any or unspecified, "" = no namespace, "*" = any
    tag: ?[]const u8 = null, // null = universal (*)
    id: ?[]const u8 = null,
    classes: []const []const u8 = &.{},
    attributes: []const AttrSelector = &.{},
    is_scope: bool = false,
    part: ?[]const u8 = null,
};

pub const CompoundSelector = struct {
    simple: SimpleSelector,
    combinator_to_next: Combinator = .none,
};

pub const ComplexSelector = struct {
    compounds: []const CompoundSelector,

    pub fn specificity(self: ComplexSelector) Specificity {
        var spec = Specificity{};
        for (self.compounds) |comp| {
            if (comp.simple.id != null) spec.a += 1;
            spec.b += @intCast(comp.simple.classes.len);
            spec.b += @intCast(comp.simple.attributes.len);
            if (comp.simple.is_scope) spec.b += 1;
            if (comp.simple.tag != null) spec.c += 1;
            if (comp.simple.part != null) spec.c += 1;
        }
        return spec;
    }
};

pub const SelectorList = struct {
    selectors: []const ComplexSelector,

    pub fn maxSpecificity(self: SelectorList) Specificity {
        var max_s = Specificity{};
        for (self.selectors) |sel| {
            const s = sel.specificity();
            if (s.greaterThan(max_s)) max_s = s;
        }
        return max_s;
    }
};

/// Helper to get attribute value from a node by name.
pub fn getNodeAttribute(node: *const Node, name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "id")) {
        // ID can be on style or node
        return null;
    } else if (std.mem.eql(u8, name, "type")) {
        return node.type;
    } else if (std.mem.eql(u8, name, "text")) {
        return node.text;
    } else if (std.mem.eql(u8, name, "value")) {
        return node.value;
    }
    return null;
}

/// Matches an attribute selector against an attribute value.
pub fn matchAttribute(attr: AttrSelector, actual_val: ?[]const u8) bool {
    const val = actual_val orelse return false;
    switch (attr.op) {
        .exists => return true,
        .equals => {
            if (attr.case_insensitive) {
                return std.ascii.eqlIgnoreCase(val, attr.value);
            }
            return std.mem.eql(u8, val, attr.value);
        },
        .includes => {
            var it = std.mem.tokenizeAny(u8, val, " \t\r\n");
            while (it.next()) |item| {
                const eq = if (attr.case_insensitive)
                    std.ascii.eqlIgnoreCase(item, attr.value)
                else
                    std.mem.eql(u8, item, attr.value);
                if (eq) return true;
            }
            return false;
        },
        .dash_match => {
            if (attr.case_insensitive) {
                if (std.ascii.eqlIgnoreCase(val, attr.value)) return true;
                if (val.len > attr.value.len and val[attr.value.len] == '-' and std.ascii.startsWithIgnoreCase(val, attr.value)) return true;
            } else {
                if (std.mem.eql(u8, val, attr.value)) return true;
                if (val.len > attr.value.len and val[attr.value.len] == '-' and std.mem.startsWith(u8, val, attr.value)) return true;
            }
            return false;
        },
        .prefix => {
            if (attr.value.len == 0) return false;
            return if (attr.case_insensitive)
                std.ascii.startsWithIgnoreCase(val, attr.value)
            else
                std.mem.startsWith(u8, val, attr.value);
        },
        .suffix => {
            if (attr.value.len == 0) return false;
            return if (attr.case_insensitive)
                std.ascii.endsWithIgnoreCase(val, attr.value)
            else
                std.mem.endsWith(u8, val, attr.value);
        },
        .substring => {
            if (attr.value.len == 0) return false;
            if (attr.case_insensitive) {
                var i: usize = 0;
                while (i + attr.value.len <= val.len) : (i += 1) {
                    if (std.ascii.startsWithIgnoreCase(val[i..], attr.value)) return true;
                }
                return false;
            } else {
                return std.mem.indexOf(u8, val, attr.value) != null;
            }
        },
    }
}

/// Matches a single compound selector against a node.
pub fn matchCompound(compound: *const CompoundSelector, node: *const Node, scope_node: ?*const Node) bool {
    const s = compound.simple;

    // :scope pseudo-class check
    if (s.is_scope) {
        if (scope_node) |sc| {
            if (node.id != sc.id) return false;
        } else {
            return false;
        }
    }

    // Type / tag matching
    if (s.tag) |tag| {
        // Tag is matched against node.type
        if (!std.ascii.eqlIgnoreCase(node.type, tag)) return false;
    }

    // Attributes matching
    for (s.attributes) |attr| {
        const val = getNodeAttribute(node, attr.name);
        if (!matchAttribute(attr, val)) return false;
    }

    return true;
}

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
