//! Backend-independent retained scene, box model and layout dispatch.
const std = @import("std");
pub const Tree = @import("tree.zig").Tree;

const style_mod = @import("style.zig");
pub const Style = style_mod.Style;

pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Edges = geometry.Edges;
pub const text_mod = @import("text.zig");
pub const Text = text_mod.Text;
pub const Metrics = text_mod.Metrics;

/// `margin: "auto"` sentinel emitted by the JS bridge.
pub const auto_margin: f32 = -1;

pub const Node = struct {
    id: u32,
    type: []const u8,
    text: []const u8 = "",
    clickable: bool = false,
    value: []const u8 = "",
    style: Style = .{},
    children: []Node = &.{},

    /// Padding ring. Buttons and inputs get the built-in 10px inset that the
    /// renderer draws, so layout and painting agree.
    pub fn padding(self: *const Node) Edges {
        const extra: f32 = if (std.mem.eql(u8, self.type, "button") or std.mem.eql(u8, self.type, "input")) 10 else 0;
        const base = self.style.padding + extra;
        return .{
            .top = if (self.style.paddingTop > 0) self.style.paddingTop else base,
            .right = if (self.style.paddingRight > 0) self.style.paddingRight else base,
            .bottom = if (self.style.paddingBottom > 0) self.style.paddingBottom else base,
            .left = if (self.style.paddingLeft > 0) self.style.paddingLeft else base,
        };
    }

    /// Border ring, per side with the uniform width as fallback.
    pub fn border(self: *const Node) Edges {
        return .{
            .top = if (self.style.borderTopWidth > 0) self.style.borderTopWidth else self.style.borderWidth,
            .right = if (self.style.borderRightWidth > 0) self.style.borderRightWidth else self.style.borderWidth,
            .bottom = if (self.style.borderBottomWidth > 0) self.style.borderBottomWidth else self.style.borderWidth,
            .left = if (self.style.borderLeftWidth > 0) self.style.borderLeftWidth else self.style.borderWidth,
        };
    }

    /// Margin ring with the `auto` sentinel preserved (`auto_margin`).
    pub fn marginRaw(self: *const Node) Edges {
        const shorthand = self.style.margin;
        return .{
            .top = if (self.style.marginTop != 0) self.style.marginTop else shorthand,
            .right = if (self.style.marginRight != 0) self.style.marginRight else shorthand,
            .bottom = if (self.style.marginBottom != 0) self.style.marginBottom else shorthand,
            .left = if (self.style.marginLeft != 0) self.style.marginLeft else shorthand,
        };
    }

    /// Margin ring with `auto` resolved to 0, for flow offsets that cannot
    /// distribute free space.
    pub fn margin(self: *const Node) Edges {
        const raw = self.marginRaw();
        return .{
            .top = if (raw.top == auto_margin) 0 else raw.top,
            .right = if (raw.right == auto_margin) 0 else raw.right,
            .bottom = if (raw.bottom == auto_margin) 0 else raw.bottom,
            .left = if (raw.left == auto_margin) 0 else raw.left,
        };
    }

    /// Border box of this node laid out at `bounds` (content box in this engine).
    pub fn borderBox(self: *const Node, bounds: Rect) Rect {
        return bounds.outset(self.border());
    }

    /// Padding box of this node laid out at `bounds`.
    pub fn paddingBox(self: *const Node, bounds: Rect) Rect {
        return bounds.inset(self.border());
    }

    pub fn fontSize(self: *const Node) f32 {
        return if (self.style.fontSize > 0) self.style.fontSize else text_mod.default_font_size;
    }
};

pub const Item = struct { node: *const Node, bounds: Rect, parent_id: ?u32 = null };

pub const Scene = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node,
    items: std.ArrayList(Item) = .empty,
    /// Backend text metrics; defaults to the headless estimator.
    text: Text = .{},

    pub fn fromTree(tree: *const Tree, width: f32, height: f32) !Scene {
        return fromTreeWithText(tree, width, height, .{});
    }

    pub fn fromTreeWithText(tree: *const Tree, width: f32, height: f32, text: Text) !Scene {
        var arena = std.heap.ArenaAllocator.init(tree.allocator);
        errdefer arena.deinit();
        const root = try arena.allocator().create(Node);
        root.* = try tree.materialize(arena.allocator(), tree.root, 0);
        var scene = Scene{ .arena = arena, .root = root, .text = text };
        try scene.layout(root, .{ .x = 0, .y = 0, .width = width, .height = height }, null);
        return scene;
    }

    pub fn init(allocator: std.mem.Allocator, json: []const u8, width: f32, height: f32) !Scene {
        return initWithText(allocator, json, width, height, .{});
    }

    pub fn initWithText(allocator: std.mem.Allocator, json: []const u8, width: f32, height: f32, text: Text) !Scene {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const root = try a.create(Node);
        root.* = try std.json.parseFromSliceLeaky(Node, a, json, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        var scene = Scene{ .arena = arena, .root = root, .text = text };
        try scene.layout(root, .{ .x = 0, .y = 0, .width = @max(width, 0), .height = @max(height, 0) }, null);
        return scene;
    }

    pub fn deinit(self: *Scene) void {
        self.arena.deinit();
    }

    /// Natural border-box height of a node's own box, excluding its margins.
    ///
    /// Flow layout adds margins itself (with collapsing), so folding them in
    /// here would double count them; callers that need outer size add
    /// `node.margin()` explicitly.
    pub fn naturalHeight(self: *const Scene, n: *const Node) f32 {
        const frame = n.padding().vertical() + n.border().vertical();
        if (n.style.height > 0) return n.style.height;
        if (std.mem.eql(u8, n.type, "text")) {
            return if (n.text.len == 0) frame else self.text.lineHeight(n.fontSize()) + frame;
        }
        var total: f32 = 0;
        if (n.style.columns.len > 0) {
            var row_height: f32 = 0;
            for (n.children, 0..) |*child, i| {
                row_height = @max(row_height, self.outerHeight(child));
                if ((i + 1) % n.style.columns.len == 0 or i + 1 == n.children.len) {
                    total += row_height + (if (i + 1 < n.children.len) n.style.gap else 0);
                    row_height = 0;
                }
            }
            return total + frame;
        }
        const is_row = std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
        if (is_row) {
            for (n.children) |*child| total = @max(total, self.outerHeight(child));
        } else {
            for (n.children) |*child| total += self.outerHeight(child);
            if (n.children.len > 1) total += n.style.gap * @as(f32, @floatFromInt(n.children.len - 1));
        }
        total += frame;
        if (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input")) total = @max(total, 44);
        return total;
    }

    /// Border box plus vertical margins: what a sibling gap has to accommodate.
    pub fn outerHeight(self: *const Scene, n: *const Node) f32 {
        return self.naturalHeight(n) + n.margin().vertical();
    }

    pub fn layout(self: *Scene, n: *const Node, bounds_in: Rect, parent_id: ?u32) std.mem.Allocator.Error!void {
        var b = bounds_in;
        if (n.style.minWidth > 0) b.width = @max(b.width, n.style.minWidth);
        if (n.style.minHeight > 0) b.height = @max(b.height, n.style.minHeight);
        if (n.style.maxWidth > 0) b.width = @min(b.width, n.style.maxWidth);
        if (n.style.maxHeight > 0) b.height = @min(b.height, n.style.maxHeight);
        if (n.style.aspectRatio > 0 and b.height == 0) b.height = b.width / n.style.aspectRatio;
        const bounds = b;
        try self.items.append(self.arena.allocator(), .{ .node = n, .bounds = bounds, .parent_id = parent_id });

        const pad = n.padding();
        const bd = n.border();
        const mg = n.margin();
        const inset_x = pad.horizontal() + bd.horizontal() + mg.horizontal();
        const inner_width = @max(0, bounds.width - inset_x);
        const inner_height = @max(0, bounds.height - (pad.vertical() + bd.vertical() + mg.vertical()));

        if (n.style.columns.len > 0) {
            var fixed: f32 = 0;
            var fractions: f32 = 0;
            for (n.style.columns) |track| {
                if (track >= 0) fixed += track else fractions -= track;
            }
            const free = @max(0, inner_width - fixed - n.style.gap * @as(f32, @floatFromInt(n.style.columns.len - 1)));
            var x: f32 = 0;
            var y: f32 = 0;
            var row_height: f32 = 0;
            for (n.children, 0..) |*child, i| {
                const column = i % n.style.columns.len;
                const track = n.style.columns[column];
                const width = if (track >= 0) track else if (fractions > 0) free * -track / fractions else 0;
                const height = self.naturalHeight(child);
                try self.layout(child, .{ .x = bounds.x + pad.left + bd.left + mg.left + x, .y = bounds.y + pad.top + bd.top + mg.top + y, .width = width, .height = height }, n.id);
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

        // Block layout (CSS block formatting context)
        if (std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "inline-block")) {
            try @import("layout_block.zig").layout(self, n, bounds, inner_width);
            return;
        }

        // Flexbox layout
        try @import("layout_flex.zig").layout(self, n, bounds, inner_width, inner_height);
    }

    pub fn hitTest(self: *const Scene, x: f32, y: f32) ?u32 {
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            const item = self.items.items[i];
            if (item.node.clickable and item.bounds.contains(x, y)) return item.node.id;
        }
        return null;
    }
};
