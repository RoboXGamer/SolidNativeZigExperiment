//! Persistent node storage for incremental bridge commits.
const std = @import("std");
const core = @import("root.zig");
const FlatNode = struct { id: u32, type: []const u8, text: []const u8 = "", value: []const u8 = "", clickable: bool = false, style: core.Style = .{}, children: []const u32 = &.{} };
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
        for (patch.nodes) |n| {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            errdefer arena.deinit();
            const a = arena.allocator();
            var copy = n;
            copy.type = try a.dupe(u8, n.type);
            copy.text = try a.dupe(u8, n.text);
            copy.value = try a.dupe(u8, n.value);
            copy.style.direction = try a.dupe(u8, n.style.direction);
            copy.style.columns = try a.dupe(f32, n.style.columns);
            copy.style.color = try a.dupe(u8, n.style.color);
            copy.style.backgroundColor = try a.dupe(u8, n.style.backgroundColor);
            copy.children = try a.dupe(u32, n.children);
            const result = try self.nodes.getOrPut(n.id);
            if (result.found_existing) result.value_ptr.arena.deinit();
            result.value_ptr.* = .{ .arena = arena, .node = copy };
        }
        for (patch.removed) |id| if (self.nodes.fetchRemove(id)) |removed| {
            var old = removed.value;
            old.arena.deinit();
        };
        const changed = self.root != patch.root or patch.nodes.len > 0 or patch.removed.len > 0;
        self.root = patch.root;
        return changed;
    }
    pub fn materialize(self: *const Tree, allocator: std.mem.Allocator, id: u32, depth: usize) anyerror!core.Node {
        if (depth > 256) return error.TreeTooDeep;
        const n = (self.nodes.get(id) orelse return error.UnknownNode).node;
        const children = try allocator.alloc(core.Node, n.children.len);
        for (n.children, 0..) |child, i| children[i] = try self.materialize(allocator, child, depth + 1);
        return .{ .id = n.id, .type = n.type, .text = n.text, .value = n.value, .clickable = n.clickable, .style = n.style, .children = children };
    }
};
