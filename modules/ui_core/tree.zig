//! Persistent node storage for incremental bridge commits.
const std = @import("std");
const core = @import("root.zig");
const inputs = @import("frame_inputs.zig");
const FlatNode = struct { id: u32, type: []const u8, text: []const u8 = "", value: []const u8 = "", placeholder: []const u8 = "", clickable: bool = false, focusable: bool = false, tabIndex: ?i32 = null, readOnly: bool = false, readWrite: bool = false, popoverOpen: bool = false, intrinsicAspectRatio: ?f32 = null, hovered: bool = false, active: bool = false, focused: bool = false, style: core.Style = .{}, children: []const u32 = &.{} };
const Patch = struct { root: u32, nodes: []const FlatNode = &.{}, updates: []const inputs.Delta = &.{}, removed: []const u32 = &.{} };
const Entry = struct { arena: std.heap.ArenaAllocator, node: FlatNode, revisions: inputs.Revisions = .{}, dirty: inputs.Dirty };
pub const Tree = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap(u32, Entry),
    root: u32 = 0,
    revisions: inputs.Revisions = .{},
    dirty: std.ArrayList(inputs.Dirty) = .empty,
    pub fn init(allocator: std.mem.Allocator) Tree {
        return .{ .allocator = allocator, .nodes = std.AutoHashMap(u32, Entry).init(allocator) };
    }
    pub fn deinit(self: *Tree) void {
        self.dirty.deinit(self.allocator);
        var it = self.nodes.valueIterator();
        while (it.next()) |entry| entry.arena.deinit();
        self.nodes.deinit();
    }
    pub fn apply(self: *Tree, json: []const u8) !bool {
        return (try self.applyChanges(json)).state;
    }
    pub fn applyChanges(self: *Tree, json: []const u8) !inputs.Changes {
        const parsed = try std.json.parseFromSlice(Patch, self.allocator, json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const patch = parsed.value;
        if (patch.root == self.root and patch.nodes.len == 0 and patch.updates.len == 0 and patch.removed.len == 0) {
            self.dirty.clearRetainingCapacity();
            return .{};
        }
        var effects: inputs.Changes = .{};
        if (patch.root != self.root or patch.removed.len > 0) effects.geometry();
        var staged = std.AutoHashMap(u32, Entry).init(self.allocator);
        defer staged.deinit();
        errdefer {
            var entries = staged.valueIterator();
            while (entries.next()) |entry| entry.arena.deinit();
        }
        for (patch.nodes) |n| {
            try self.stage(&staged, n, &effects, null);
        }
        for (patch.updates) |delta| {
            var n = (self.nodes.get(delta.id) orelse return error.UnknownNode).node;
            delta.apply(&n);
            try self.stage(&staged, n, &effects, delta);
        }
        try self.dirty.ensureTotalCapacity(self.allocator, staged.count());
        var structural = patch.root != self.root or patch.removed.len > 0;
        var inspect = staged.iterator();
        while (inspect.next()) |entry| {
            const old = self.nodes.get(entry.key_ptr.*) orelse {
                structural = true;
                break;
            };
            if (!std.mem.eql(u32, old.node.children, entry.value_ptr.node.children)) {
                structural = true;
                break;
            }
        }
        if (!structural) {
            // Existing identities and unchanged edges cannot invalidate graph
            // reachability. Commit only the changed entries, with no N-node map
            // clone, validation walk, or old-entry scan on this path.
            self.dirty.clearRetainingCapacity();
            var updates = staged.iterator();
            while (updates.next()) |entry| {
                const old = self.nodes.getPtr(entry.key_ptr.*).?;
                old.arena.deinit();
                old.* = entry.value_ptr.*;
                if (old.dirty.paint or old.dirty.interaction or old.dirty.motion) self.dirty.appendAssumeCapacity(old.dirty);
            }
            self.revisions.advance(effects);
            return effects;
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
        var old = self.nodes.iterator();
        while (old.next()) |entry| {
            if (staged.contains(entry.key_ptr.*) or !next.contains(entry.key_ptr.*)) entry.value_ptr.arena.deinit();
        }
        self.nodes.deinit();
        self.nodes = next;
        self.root = patch.root;
        self.dirty.clearRetainingCapacity();
        var dirty_entries = staged.valueIterator();
        while (dirty_entries.next()) |entry| if (entry.dirty.paint or entry.dirty.interaction or entry.dirty.motion) {
            self.dirty.appendAssumeCapacity(entry.dirty);
        };
        self.revisions.advance(effects);
        return effects;
    }
    fn stage(self: *Tree, staged: *std.AutoHashMap(u32, Entry), n: FlatNode, effects: *inputs.Changes, delta: ?inputs.Delta) !void {
        if (staged.contains(n.id)) return error.DuplicateNode;
        var node_effects: inputs.Changes = .{};
        var revisions: inputs.Revisions = .{};
        var dirty: inputs.Dirty = .{ .id = n.id, .paint = true, .interaction = true, .motion = true };
        if (self.nodes.get(n.id)) |previous| {
            dirty = inputs.Dirty.between(previous.node, n);
            node_effects = if (delta) |update| update.effects(previous.node) else inputs.difference(previous.node, n);
            revisions = previous.revisions;
        } else node_effects.geometry();
        effects.merge(node_effects);
        revisions.advance(node_effects);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        var copy = n;
        copy.type = try a.dupe(u8, n.type);
        copy.text = try a.dupe(u8, n.text);
        copy.value = try a.dupe(u8, n.value);
        copy.placeholder = try a.dupe(u8, n.placeholder);
        const s_info = @typeInfo(core.Style).@"struct";
        inline for (s_info.field_names, s_info.field_types) |fname, ftype| {
            if (ftype == []const u8) {
                @field(copy.style, fname) = try a.dupe(u8, @field(n.style, fname));
            } else if (ftype == ?[]const u8) {
                if (@field(n.style, fname)) |value| @field(copy.style, fname) = try a.dupe(u8, value);
            }
        }
        copy.children = try a.dupe(u32, n.children);
        try staged.put(n.id, .{ .arena = arena, .node = copy, .revisions = revisions, .dirty = dirty });
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
        var style = n.style;
        inline for (@typeInfo(core.Style).@"struct".field_names, @typeInfo(core.Style).@"struct".field_types) |name, T| {
            if (T == []const u8) @field(style, name) = try allocator.dupe(u8, @field(style, name)) else if (T == ?[]const u8) {
                if (@field(style, name)) |value| @field(style, name) = try allocator.dupe(u8, value);
            }
        }
        return .{ .id = n.id, .type = try allocator.dupe(u8, n.type), .text = try allocator.dupe(u8, n.text), .value = try allocator.dupe(u8, n.value), .placeholder = try allocator.dupe(u8, n.placeholder), .clickable = n.clickable, .focusable = n.focusable, .tabIndex = n.tabIndex, .readOnly = n.readOnly, .readWrite = n.readWrite, .popoverOpen = n.popoverOpen, .intrinsicAspectRatio = n.intrinsicAspectRatio, .hovered = n.hovered, .active = n.active, .focused = n.focused, .style = style, .children = children };
    }
};
