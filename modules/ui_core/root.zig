//! Backend-independent retained scene and basic row/column layout.
const std = @import("std");
pub const Tree = @import("tree.zig").Tree;

pub const Style = struct {
    direction: []const u8 = "column",
    flexDirection: []const u8 = "row",
    flexWrap: []const u8 = "nowrap",
    justifyContent: []const u8 = "flex-start",
    alignItems: []const u8 = "stretch",
    alignContent: []const u8 = "stretch",
    alignSelf: []const u8 = "auto",
    flexGrow: f32 = 0,
    flexShrink: f32 = 1,
    flexBasis: f32 = 0,
    order: i32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    minWidth: f32 = 0,
    minHeight: f32 = 0,
    maxWidth: f32 = 0,
    maxHeight: f32 = 0,
    aspectRatio: f32 = 0,
    padding: f32 = 0,
    paddingTop: f32 = 0,
    paddingRight: f32 = 0,
    paddingBottom: f32 = 0,
    paddingLeft: f32 = 0,
    margin: f32 = 0,
    marginTop: f32 = 0,
    marginRight: f32 = 0,
    marginBottom: f32 = 0,
    marginLeft: f32 = 0,
    gap: f32 = 0,
    columns: []const f32 = &.{},
    backgroundColor: []const u8 = "",
    borderColor: []const u8 = "",
    borderTopColor: []const u8 = "",
    borderRightColor: []const u8 = "",
    borderBottomColor: []const u8 = "",
    borderLeftColor: []const u8 = "",
    borderWidth: f32 = 0,
    borderTopWidth: f32 = 0,
    borderRightWidth: f32 = 0,
    borderBottomWidth: f32 = 0,
    borderLeftWidth: f32 = 0,
    borderRadius: f32 = 0,
    borderTopLeftRadius: f32 = 0,
    borderTopRightRadius: f32 = 0,
    borderBottomRightRadius: f32 = 0,
    borderBottomLeftRadius: f32 = 0,
    boxSizing: []const u8 = "border-box",
    overflow: []const u8 = "visible",
    outlineWidth: f32 = 0,
    outlineColor: []const u8 = "",
    boxShadow: []const u8 = "",
    color: []const u8 = "",
    fontSize: f32 = 0,
};
pub const Node = struct {
    id: u32,
    type: []const u8,
    text: []const u8 = "",
    clickable: bool = false,
    value: []const u8 = "",
    style: Style = .{},
    children: []Node = &.{},
};
pub const Rect = struct { x: f32, y: f32, width: f32, height: f32 };
pub const Item = struct { node: *const Node, bounds: Rect, parent_id: ?u32 = null };
pub const Scene = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node,
    items: std.ArrayList(Item) = .empty,
    pub fn fromTree(tree: *const Tree, width: f32, height: f32) !Scene {
        var arena = std.heap.ArenaAllocator.init(tree.allocator);
        errdefer arena.deinit();
        const root = try arena.allocator().create(Node);
        root.* = try tree.materialize(arena.allocator(), tree.root, 0);
        var scene = Scene{ .arena = arena, .root = root };
        try scene.layout(root, .{ .x = 0, .y = 0, .width = width, .height = height }, null);
        return scene;
    }

    pub fn init(allocator: std.mem.Allocator, json: []const u8, width: f32, height: f32) !Scene {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const root = try a.create(Node);
        root.* = try std.json.parseFromSliceLeaky(Node, a, json, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        var scene = Scene{ .arena = arena, .root = root };
        try scene.layout(root, .{ .x = 0, .y = 0, .width = @max(width, 0), .height = @max(height, 0) }, null);
        return scene;
    }
    pub fn deinit(self: *Scene) void {
        self.arena.deinit();
    }
    fn naturalHeight(n: *const Node) f32 {
        if (n.style.height > 0) return n.style.height;
        if (std.mem.eql(u8, n.type, "text")) return if (n.text.len == 0) 0 else if (n.style.fontSize > 0) n.style.fontSize + 6 else 26;
        var total: f32 = 0;
        if (n.style.columns.len > 0) {
            var row_height: f32 = 0;
            for (n.children, 0..) |*child, i| {
                row_height = @max(row_height, naturalHeight(child));
                if ((i + 1) % n.style.columns.len == 0 or i + 1 == n.children.len) {
                    total += row_height + (if (i + 1 < n.children.len) n.style.gap else 0);
                    row_height = 0;
                }
            }
            const pt2 = if (n.style.paddingTop > 0) n.style.paddingTop else n.style.padding;
            const pb2 = if (n.style.paddingBottom > 0) n.style.paddingBottom else n.style.padding;
            const bt2 = if (n.style.borderTopWidth > 0) n.style.borderTopWidth else n.style.borderWidth;
            const bb2 = if (n.style.borderBottomWidth > 0) n.style.borderBottomWidth else n.style.borderWidth;
            const mt2 = if (n.style.marginTop > 0) n.style.marginTop else n.style.margin;
            const mb2 = if (n.style.marginBottom > 0) n.style.marginBottom else n.style.margin;
            return total + (pt2 + pb2 + bt2 + bb2 + mt2 + mb2);
        }
        const row = std.mem.eql(u8, n.style.direction, "row");
        for (n.children) |*child| {
            const h = naturalHeight(child);
            total = if (row) @max(total, h) else total + h;
        }
        if (!row and n.children.len > 1) total += n.style.gap * @as(f32, @floatFromInt(n.children.len - 1));
        const pt3 = if (n.style.paddingTop > 0) n.style.paddingTop else n.style.padding + (if (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input")) @as(f32, 10) else 0);
        const pb3 = if (n.style.paddingBottom > 0) n.style.paddingBottom else n.style.padding + (if (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input")) @as(f32, 10) else 0);
        const bt3 = if (n.style.borderTopWidth > 0) n.style.borderTopWidth else n.style.borderWidth;
        const bb3 = if (n.style.borderBottomWidth > 0) n.style.borderBottomWidth else n.style.borderWidth;
        const mt3 = if (n.style.marginTop > 0) n.style.marginTop else n.style.margin;
        const mb3 = if (n.style.marginBottom > 0) n.style.marginBottom else n.style.margin;
        total += (pt3 + pb3 + bt3 + bb3 + mt3 + mb3);
        if (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input")) total = @max(total + 20, 44);
        return total;
    }
    fn layout(self: *Scene, n: *const Node, bounds_in: Rect, parent_id: ?u32) std.mem.Allocator.Error!void {
        var b = bounds_in;
        if (n.style.minWidth > 0) b.width = @max(b.width, n.style.minWidth);
        if (n.style.minHeight > 0) b.height = @max(b.height, n.style.minHeight);
        if (n.style.maxWidth > 0) b.width = @min(b.width, n.style.maxWidth);
        if (n.style.maxHeight > 0) b.height = @min(b.height, n.style.maxHeight);
        if (n.style.aspectRatio > 0 and b.height == 0) b.height = b.width / n.style.aspectRatio;
        const bounds = b;
        try self.items.append(self.arena.allocator(), .{ .node = n, .bounds = bounds, .parent_id = parent_id });
        const row = std.mem.eql(u8, n.style.direction, "row");
        const pt = if (n.style.paddingTop > 0) n.style.paddingTop else n.style.padding + (if (std.mem.eql(u8, n.type, "button")) @as(f32, 10) else 0);
        const pr = if (n.style.paddingRight > 0) n.style.paddingRight else n.style.padding + (if (std.mem.eql(u8, n.type, "button")) @as(f32, 10) else 0);
        const pl = if (n.style.paddingLeft > 0) n.style.paddingLeft else n.style.padding + (if (std.mem.eql(u8, n.type, "button")) @as(f32, 10) else 0);
        const bt = if (n.style.borderTopWidth > 0) n.style.borderTopWidth else n.style.borderWidth;
        const br = if (n.style.borderRightWidth > 0) n.style.borderRightWidth else n.style.borderWidth;
        const bl = if (n.style.borderLeftWidth > 0) n.style.borderLeftWidth else n.style.borderWidth;
        const mt = if (n.style.marginTop > 0) n.style.marginTop else n.style.margin;
        const mr = if (n.style.marginRight > 0) n.style.marginRight else n.style.margin;
        const ml = if (n.style.marginLeft > 0) n.style.marginLeft else n.style.margin;
        const inset_x = pl + bl + ml + pr + br + mr;
        const inner_width = @max(0, bounds.width - inset_x);
        if (n.style.columns.len > 0) {
            var fixed: f32 = 0;
            var fractions: f32 = 0;
            for (n.style.columns) |track| {
                if (track >= 0) {
                    fixed += track;
                } else {
                    fractions -= track;
                }
            }
            const free = @max(0, inner_width - fixed - n.style.gap * @as(f32, @floatFromInt(n.style.columns.len - 1)));
            var x: f32 = 0;
            var y: f32 = 0;
            var row_height: f32 = 0;
            for (n.children, 0..) |*child, i| {
                const column = i % n.style.columns.len;
                const track = n.style.columns[column];
                const width = if (track >= 0) track else if (fractions > 0) free * -track / fractions else 0;
                const height = naturalHeight(child);
                try self.layout(child, .{ .x = bounds.x + pl + bl + ml + x, .y = bounds.y + pt + bt + mt + y, .width = width, .height = height }, n.id);
                row_height = @max(row_height, height);
                x += width + n.style.gap;
                if (column + 1 == n.style.columns.len) {
                    x = 0;
                    y += row_height + n.style.gap;
                    row_height = 0;
                }
            }
            return;
        }
        const count: f32 = @floatFromInt(@max(n.children.len, 1));
        const row_width = @max(0, (inner_width - @max(count - 1, 0) * n.style.gap) / count);
        var offset: f32 = 0;
        for (n.children) |*child| {
            const child_inset_x = (if (child.style.paddingLeft > 0) child.style.paddingLeft else child.style.padding) + (if (child.style.borderLeftWidth > 0) child.style.borderLeftWidth else child.style.borderWidth) + (if (child.style.paddingRight > 0) child.style.paddingRight else child.style.padding) + (if (child.style.borderRightWidth > 0) child.style.borderRightWidth else child.style.borderWidth);
            const child_w = if (child.style.width > 0) @min(if (std.mem.eql(u8, child.style.boxSizing, "content-box")) child.style.width + child_inset_x else child.style.width, inner_width) else if (row and std.mem.eql(u8, child.type, "text")) @min(inner_width, @as(f32, @floatFromInt(child.text.len)) * (if (child.style.fontSize > 0) child.style.fontSize * 0.6 else 10)) else if (row) row_width else inner_width;
            const child_h = naturalHeight(child);
            const cml = if (child.style.marginLeft > 0) child.style.marginLeft else child.style.margin;
            const cmt = if (child.style.marginTop > 0) child.style.marginTop else child.style.margin;
            const child_bounds = Rect{ .x = bounds.x + pl + bl + ml + cml + (if (row) offset else 0), .y = bounds.y + pt + bt + mt + cmt + (if (row) 0 else offset), .width = child_w, .height = child_h };
            try self.layout(child, child_bounds, n.id);
            offset += (if (row) child_w else child_h) + n.style.gap;
        }
    }
    pub fn hitTest(self: *const Scene, x: f32, y: f32) ?u32 {
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            const item = self.items.items[i];
            const b = item.bounds;
            if (item.node.clickable and x >= b.x and y >= b.y and x < b.x + b.width and y < b.y + b.height) return item.node.id;
        }
        return null;
    }
};

test "layout and hit testing use node identity" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"button","clickable":true,"children":[{"id":3,"type":"text","text":"Click"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(?u32, 2), scene.hitTest(5, 5));
    try std.testing.expectEqual(@as(?u32, null), scene.hitTest(301, 5));
}

test "row layout gives separate buttons separate hit targets" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"row","style":{"direction":"row","gap":10},"children":[{"id":3,"type":"button","clickable":true},{"id":4,"type":"button","clickable":true}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(?u32, 3), scene.hitTest(20, 10));
    try std.testing.expectEqual(@as(?u32, 4), scene.hitTest(200, 10));
    try std.testing.expectEqual(@as(?u32, null), scene.hitTest(150, 10));
}

test "per-side padding and border affect layout" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"paddingTop":5,"paddingBottom":7,"borderLeftWidth":2,"borderRightWidth":3,"margin":4},"children":[{"id":3,"type":"text","text":"hi"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expect(b.x > 0);
    try std.testing.expect(b.width <= 300);
}

test "nested overflow parent tracking" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"overflow":"hidden"},"children":[{"id":3,"type":"text","text":"hi"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const child = scene.items.items[2];
    try std.testing.expectEqual(@as(?u32, 2), child.parent_id);
}

test "min/max and aspect ratio constraints" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"minWidth":50,"maxWidth":100,"aspectRatio":2},"children":[]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 200);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expect(b.width >= 50 and b.width <= 100);
    try std.testing.expect(b.height > 0);
}

test "incremental tree keeps unchanged nodes and releases deleted nodes" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();
    _ = try tree.apply("{\"root\":1,\"nodes\":[{\"id\":1,\"type\":\"root\",\"children\":[2]},{\"id\":2,\"type\":\"text\",\"text\":\"before\"}]}");
    _ = try tree.apply("{\"root\":1,\"nodes\":[{\"id\":2,\"type\":\"text\",\"text\":\"after\"}]}");
    var scene = try Scene.fromTree(&tree, 300, 200);
    try std.testing.expectEqualStrings("after", scene.root.children[0].text);
    scene.deinit();
    _ = try tree.apply("{\"root\":1,\"nodes\":[{\"id\":1,\"type\":\"root\"}],\"removed\":[2]}");
    try std.testing.expectEqual(@as(usize, 1), tree.nodes.count());
}
