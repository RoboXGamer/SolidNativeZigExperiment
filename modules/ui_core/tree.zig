//! Persistent node storage for incremental bridge commits.
const std = @import("std");
const core = @import("root.zig");
const FlatNode = struct { id: u32, type: []const u8, text: []const u8 = "", value: []const u8 = "", clickable: bool = false, focusable: bool = false, tabIndex: ?i32 = null, intrinsicAspectRatio: ?f32 = null, style: core.Style = .{}, children: []const u32 = &.{} };
const Patch = struct { root: u32, nodes: []const FlatNode = &.{}, removed: []const u32 = &.{} };
const Entry = struct { arena: std.heap.ArenaAllocator, node: FlatNode };
pub const Tree = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap(u32, Entry),
    root: u32 = 0,
    pub fn init(allocator: std.mem.Allocator) Tree {
        return .{ .allocator = allocator, .nodes = std.AutoHashMap(u32, Entry).init(allocator) };
    }
    pub fn deinit(self: *Tree) void {
        var it = self.nodes.valueIterator();
        while (it.next()) |entry| entry.arena.deinit();
        self.nodes.deinit();
    }
    pub fn apply(self: *Tree, json: []const u8) !bool {
        const parsed = try std.json.parseFromSlice(Patch, self.allocator, json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const patch = parsed.value;
        if (patch.root == self.root and patch.nodes.len == 0 and patch.removed.len == 0) return false;
        var staged = std.AutoHashMap(u32, Entry).init(self.allocator);
        defer staged.deinit();
        errdefer {
            var entries = staged.valueIterator();
            while (entries.next()) |entry| entry.arena.deinit();
        }
        for (patch.nodes) |n| {
            if (staged.contains(n.id)) return error.DuplicateNode;
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            errdefer arena.deinit();
            const a = arena.allocator();
            var copy = n;
            copy.type = try a.dupe(u8, n.type);
            copy.text = try a.dupe(u8, n.text);
            copy.value = try a.dupe(u8, n.value);
            copy.style.columns = try a.dupe(f32, n.style.columns);
            const s_info = @typeInfo(core.Style).@"struct";
            inline for (s_info.field_names, s_info.field_types) |fname, ftype| {
                if (ftype == []const u8) {
                    @field(copy.style, fname) = try a.dupe(u8, @field(n.style, fname));
                } else if (ftype == ?[]const u8) {
                    if (@field(n.style, fname)) |value| @field(copy.style, fname) = try a.dupe(u8, value);
                }
            }
            copy.children = try a.dupe(u32, n.children);
            try staged.put(n.id, .{ .arena = arena, .node = copy });
        }
        var next = try self.nodes.clone();
        errdefer next.deinit();
        var changes = staged.iterator();
        while (changes.next()) |entry| try next.put(entry.key_ptr.*, entry.value_ptr.*);
        for (patch.removed) |id| {
            if (staged.contains(id)) return error.ConflictingRemoval;
            _ = next.remove(id);
        }
        var visited = std.AutoHashMap(u32, void).init(self.allocator);
        defer visited.deinit();
        try validate(&next, &visited, patch.root, 0);
        if (visited.count() != next.count()) return error.UnreachableNode;
        const changed = self.root != patch.root or patch.nodes.len > 0 or patch.removed.len > 0;
        var old = self.nodes.iterator();
        while (old.next()) |entry| {
            if (staged.contains(entry.key_ptr.*) or !next.contains(entry.key_ptr.*)) entry.value_ptr.arena.deinit();
        }
        self.nodes.deinit();
        self.nodes = next;
        self.root = patch.root;
        return changed;
    }

    fn validate(nodes: *const std.AutoHashMap(u32, Entry), visited: *std.AutoHashMap(u32, void), id: u32, depth: usize) anyerror!void {
        if (depth > 256) return error.TreeTooDeep;
        if (visited.contains(id)) return error.CyclicOrSharedNode;
        const entry = nodes.get(id) orelse return error.UnknownNode;
        try visited.put(id, {});
        for (entry.node.children) |child| try validate(nodes, visited, child, depth + 1);
    }
    pub fn materialize(self: *const Tree, allocator: std.mem.Allocator, id: u32, depth: usize) anyerror!core.Node {
        if (depth > 256) return error.TreeTooDeep;
        const n = (self.nodes.get(id) orelse return error.UnknownNode).node;
        const children = try allocator.alloc(core.Node, n.children.len);
        for (n.children, 0..) |child, i| children[i] = try self.materialize(allocator, child, depth + 1);
        return .{ .id = n.id, .type = n.type, .text = n.text, .value = n.value, .clickable = n.clickable, .focusable = n.focusable, .tabIndex = n.tabIndex, .intrinsicAspectRatio = n.intrinsicAspectRatio, .style = n.style, .children = children };
    }
};
