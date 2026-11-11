//! Backend-independent retained scene, box model and layout dispatch.
const std = @import("std");
pub const Tree = @import("tree.zig").Tree;

const style_mod = @import("style.zig");
const sizing = @import("sizing.zig");
pub const Style = style_mod.Style;

pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Edges = geometry.Edges;
pub const text_mod = @import("text.zig");
pub const Text = text_mod.Text;
pub const Metrics = text_mod.Metrics;

pub const Node = struct {
    id: u32,
    type: []const u8,
    text: []const u8 = "",
    clickable: bool = false,
    value: []const u8 = "",
    /// Optional input for a future replaced-element measurement provider.
    intrinsicAspectRatio: ?f32 = null,
    style: Style = .{},
    children: []Node = &.{},

    /// Padding ring; controls provide a default which author values override.
    pub fn padding(self: *const Node) Edges {
        const default: f32 = if (std.mem.eql(u8, self.type, "button") or std.mem.eql(u8, self.type, "input")) 10 else 0;
        const base = self.style.padding orelse default;
        return .{
            .top = self.style.paddingTop orelse base,
            .right = self.style.paddingRight orelse base,
            .bottom = self.style.paddingBottom orelse base,
            .left = self.style.paddingLeft orelse base,
        };
    }

    /// Border ring, per side with the uniform width as fallback.
    pub fn border(self: *const Node) Edges {
        return .{
            .top = self.style.borderTopWidth orelse self.style.borderWidth,
            .right = self.style.borderRightWidth orelse self.style.borderWidth,
            .bottom = self.style.borderBottomWidth orelse self.style.borderWidth,
            .left = self.style.borderLeftWidth orelse self.style.borderWidth,
        };
    }

    /// Fixed margin lengths; automatic sides resolve to zero until allocated.
    pub fn margin(self: *const Node) Edges {
        const shorthand = self.style.margin;
        return .{
            .top = if (self.style.marginTopAuto) 0 else self.style.marginTop orelse shorthand,
            .right = if (self.style.marginRightAuto) 0 else self.style.marginRight orelse shorthand,
            .bottom = if (self.style.marginBottomAuto) 0 else self.style.marginBottom orelse shorthand,
            .left = if (self.style.marginLeftAuto) 0 else self.style.marginLeft orelse shorthand,
        };
    }

    /// Layout bounds are the border box, excluding the node's margins.
    pub fn borderBox(self: *const Node, bounds: Rect) Rect {
        _ = self;
        return bounds;
    }

    /// Padding box of this node laid out at `bounds`.
    pub fn paddingBox(self: *const Node, bounds: Rect) Rect {
        return bounds.inset(self.border());
    }

    pub fn contentBox(self: *const Node, bounds: Rect) Rect {
        return self.paddingBox(bounds).inset(self.padding());
    }

    pub fn marginBox(self: *const Node, bounds: Rect) Rect {
        return bounds.outset(self.margin());
    }

    pub fn borderSize(self: *const Node, value: f32, frame: f32) f32 {
        return @max(frame, value + if (std.mem.eql(u8, self.style.boxSizing, "content-box")) frame else @as(f32, 0));
    }

    pub fn constrain(self: *const Node, value: f32, horizontal: bool) f32 {
        const frame = if (horizontal) self.padding().horizontal() + self.border().horizontal() else self.padding().vertical() + self.border().vertical();
        const minimum = if (horizontal) self.style.minWidth else self.style.minHeight;
        const maximum = if (horizontal) self.style.maxWidth else self.style.maxHeight;
        var used = @max(frame, value);
        if (maximum) |max| used = @min(used, self.borderSize(max, frame));
        if (minimum) |min| used = @max(used, self.borderSize(min, frame));
        return @max(frame, used);
    }

    pub fn fontSize(self: *const Node) f32 {
        return if (self.style.fontSize > 0) self.style.fontSize else text_mod.default_font_size;
    }

    pub fn aspectRatio(self: *const Node) ?f32 {
        const value = self.style.aspectRatio orelse self.intrinsicAspectRatio orelse return null;
        return if (std.math.isFinite(value) and value > 0) value else null;
    }
};

pub const Item = struct { node: *const Node, bounds: Rect, parent_id: ?u32 = null };

// The retained tree stays untouched: contents only disappears from this layout
// projection, so Solid's node identities and event-parent links remain intact.
fn appendGenerated(a: std.mem.Allocator, out: *std.ArrayList(Node), source: Node) anyerror!void {
    const display = source.style.display;
    if (std.mem.eql(u8, display, "none")) return;
    if (std.mem.eql(u8, display, "contents")) {
        for (source.children) |child| try appendGenerated(a, out, child);
        return;
    }
    if (!std.mem.eql(u8, display, "block") and !std.mem.eql(u8, display, "flow-root") and
        !std.mem.eql(u8, display, "flex") and !std.mem.eql(u8, display, "grid")) return error.UnsupportedDisplay;
    var children: std.ArrayList(Node) = .empty;
    for (source.children) |child| try appendGenerated(a, &children, child);
    var copy = source;
    copy.children = try children.toOwnedSlice(a);
    try out.append(a, copy);
}

fn generateRoot(a: std.mem.Allocator, source: Node) !*Node {
    var generated: std.ArrayList(Node) = .empty;
    try appendGenerated(a, &generated, source);
    const root = try a.create(Node);
    // A suppressed root still has a scene object but no painted/hit boxes.
    root.* = if (generated.items.len == 1) generated.items[0] else .{
        .id = source.id,
        .type = "__layout_root",
        .style = .{ .display = "block" },
        .children = try generated.toOwnedSlice(a),
    };
    return root;
}

pub const Scene = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node,
    items: std.ArrayList(Item) = .empty,
    index: std.AutoHashMapUnmanaged(u32, usize) = .empty,
    /// Backend text metrics; defaults to the headless estimator.
    text: Text = .{},
    length_context: sizing.Context = .{},
    viewport: Rect = .{},

    fn intrinsicWidth(self: *const Scene, n: *const Node, minimum: bool) f32 {
        const frame = n.padding().horizontal() + n.border().horizontal();
        if (std.mem.eql(u8, n.type, "text")) return frame + if (minimum) self.text.minContentWidth(n.text, n.fontSize()) else self.text.maxContentWidth(n.text, n.fontSize());
        const row = std.mem.eql(u8, n.style.display, "flex") and (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        var width: f32 = 0;
        for (n.children, 0..) |*child, i| {
            const child_frame = child.padding().horizontal() + child.border().horizontal();
            const contribution = if (child.style.width) |v| child.constrain(child.borderSize(v, child_frame), true) else child.constrain(self.intrinsicWidth(child, minimum), true);
            const child_width = contribution + child.margin().horizontal();
            if (row) {
                if (i > 0) width += n.style.gap;
                width += child_width;
            } else width = @max(width, child_width);
        }
        return width + frame;
    }

    /// Border-box intrinsic contribution, without this node's margins.
    pub fn intrinsicWidthFor(self: *const Scene, n: *const Node, space: sizing.AvailableSpace) f32 {
        const min = self.intrinsicWidth(n, true);
        const max = self.intrinsicWidth(n, false);
        return switch (space) {
            .min_content => min,
            .max_content => max,
            .definite => |available| @min(max, @max(min, available)),
        };
    }

    fn intrinsicHeight(self: *const Scene, n: *const Node) f32 {
        const frame = n.padding().vertical() + n.border().vertical();
        if (std.mem.eql(u8, n.type, "text")) return frame + if (n.text.len == 0) @as(f32, 0) else self.text.lineHeight(n.fontSize());
        const row = std.mem.eql(u8, n.style.display, "flex") and (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        var height: f32 = 0;
        for (n.children, 0..) |*child, i| {
            const child_frame = child.padding().vertical() + child.border().vertical();
            const contribution = if (child.style.height) |v| child.constrain(child.borderSize(v, child_frame), false) else child.constrain(self.intrinsicHeight(child), false);
            const child_height = contribution + child.margin().vertical();
            if (row) height = @max(height, child_height) else {
                if (i > 0 and std.mem.eql(u8, n.style.display, "flex")) height += n.style.gap;
                height += child_height;
            }
        }
        return height + frame;
    }

    fn resolveStyle(self: *const Scene, n: *Node, context: sizing.Context, containing_width: ?f32, containing_height: ?f32, inline_size: ?f32) !void {
        if (!std.mem.eql(u8, n.style.boxSizing, "content-box") and !std.mem.eql(u8, n.style.boxSizing, "border-box")) return error.InvalidBoxSizing;
        inline for (.{ "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "marginTop", "marginRight", "marginBottom", "marginLeft", "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight" }) |name| {
            if (@field(n.style, name)) |number| {
                if (!std.math.isFinite(number) or (number < 0 and !std.mem.startsWith(u8, name, "margin"))) return error.InvalidLength;
            }
            if (@field(n.style, name ++ "Css")) |css| {
                if (std.mem.startsWith(u8, name, "border") and std.mem.indexOfScalar(u8, css, '%') != null) return error.InvalidLength;
                var ctx = context;
                ctx.font_size = n.fontSize();
                ctx.percentage = if (std.mem.eql(u8, name, "height") or std.mem.eql(u8, name, "minHeight") or std.mem.eql(u8, name, "maxHeight")) containing_height else if (std.mem.eql(u8, name, "width") or std.mem.eql(u8, name, "minWidth") or std.mem.eql(u8, name, "maxWidth")) containing_width else inline_size;
                const is_fit_function = std.mem.startsWith(u8, css, "fit-content(") and std.mem.endsWith(u8, css, ")");
                const value: sizing.Resolution = if (is_fit_function) .{ .keyword = .fit_content } else try sizing.resolve(css, ctx);
                switch (value) {
                    .length => |number| {
                        if (number < 0 and !std.mem.startsWith(u8, name, "margin")) return error.NegativeSize;
                        @field(n.style, name) = number;
                    },
                    .keyword => |keyword| {
                        if (keyword == .auto and (std.mem.eql(u8, name, "width") or std.mem.eql(u8, name, "height") or std.mem.startsWith(u8, name, "min"))) {
                            @field(n.style, name) = null;
                        } else if (keyword == .none and std.mem.startsWith(u8, name, "max")) {
                            @field(n.style, name) = null;
                        } else if ((keyword == .min_content or keyword == .max_content or keyword == .fit_content) and (std.mem.eql(u8, name, "width") or std.mem.eql(u8, name, "minWidth") or std.mem.eql(u8, name, "maxWidth"))) {
                            const min = self.intrinsicWidth(n, true);
                            const max = self.intrinsicWidth(n, false);
                            var cap = containing_width;
                            if (is_fit_function) {
                                const limit = try sizing.resolve(css[12 .. css.len - 1], ctx);
                                cap = switch (limit) {
                                    .length => |v| if (v < 0) return error.NegativeSize else n.borderSize(v, n.padding().horizontal() + n.border().horizontal()),
                                    else => return error.UnresolvedLengthContext,
                                };
                            }
                            const border_width = switch (keyword) {
                                .min_content => min,
                                .max_content => max,
                                .fit_content => if (cap) |c| @min(max, @max(min, c)) else max,
                                else => unreachable,
                            };
                            const frame = n.padding().horizontal() + n.border().horizontal();
                            @field(n.style, name) = if (std.mem.eql(u8, n.style.boxSizing, "content-box")) @max(0, border_width - frame) else border_width;
                        } else if ((keyword == .min_content or keyword == .max_content or keyword == .fit_content) and (std.mem.eql(u8, name, "height") or std.mem.eql(u8, name, "minHeight") or std.mem.eql(u8, name, "maxHeight"))) {
                            const height = self.intrinsicHeight(n);
                            const frame = n.padding().vertical() + n.border().vertical();
                            @field(n.style, name) = if (std.mem.eql(u8, n.style.boxSizing, "content-box")) @max(0, height - frame) else height;
                        } else return error.UnsupportedSizingKeyword;
                    },
                    .unresolved => {
                        // An indefinite percentage dimension computes as auto here;
                        // unavailable font/container metrics are explicit errors.
                        if (ctx.percentage != null or std.mem.indexOfScalar(u8, css, '%') == null) return error.UnresolvedLengthContext;
                        if (!std.mem.eql(u8, name, "height") and !std.mem.eql(u8, name, "minHeight") and !std.mem.eql(u8, name, "maxHeight")) return error.UnresolvedLengthContext;
                        ctx.percentage = 0;
                        switch (try sizing.resolve(css, ctx)) {
                            .length => {},
                            else => return error.UnresolvedLengthContext,
                        }
                        @field(n.style, name) = null;
                    },
                }
            }
        }
        if (n.style.padding) |value| if (!std.math.isFinite(value) or value < 0) return error.InvalidLength;
        if (!std.math.isFinite(n.style.margin) or !std.math.isFinite(n.style.borderWidth) or n.style.borderWidth < 0) return error.InvalidLength;
        if (n.style.flexBasis) |value| if (!std.math.isFinite(value) or value < 0) return error.InvalidLength;
        if (n.style.aspectRatio) |value| if (!std.math.isFinite(value) or value <= 0) return error.InvalidLength;
        if (n.intrinsicAspectRatio) |value| if (!std.math.isFinite(value) or value <= 0) return error.InvalidLength;
    }

    fn prepareChildren(self: *Scene, n: *Node, width: f32, height: ?f32) anyerror!void {
        n.children = try self.arena.allocator().dupe(Node, n.children);
        for (n.children) |*child| {
            const vertical = !std.mem.eql(u8, n.style.writingMode, "horizontal-tb");
            const inline_size: ?f32 = if (vertical) height else width;
            try self.resolveStyle(child, self.length_context, width, height, inline_size);
            if (child.style.flexBasisCss) |css| {
                var context = self.length_context;
                context.font_size = child.fontSize();
                const row = std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
                context.percentage = if (row) width else height;
                switch (try sizing.resolve(css, context)) {
                    .length => |value| {
                        if (value < 0) return error.NegativeSize;
                        child.style.flexBasis = value;
                    },
                    .unresolved => {
                        if (context.percentage != null or std.mem.indexOfScalar(u8, css, '%') == null) return error.UnresolvedLengthContext;
                        context.percentage = 0;
                        switch (try sizing.resolve(css, context)) {
                            .length => {},
                            else => return error.UnresolvedLengthContext,
                        }
                        child.style.flexBasis = null;
                    },
                    else => return error.UnsupportedSizingKeyword,
                }
            }
            const frame_w = child.padding().horizontal() + child.border().horizontal();
            const frame_h = child.padding().vertical() + child.border().vertical();
            const child_w = if (child.style.width) |v| child.borderSize(v, frame_w) else width;
            const child_h: ?f32 = if (child.style.height) |v| child.borderSize(v, frame_h) else null;
            try self.prepareChildren(child, @max(0, child_w - frame_w), if (child_h) |h| @max(0, h - frame_h) else null);
            try self.resolveStyle(child, self.length_context, width, height, inline_size);
        }
    }

    pub fn fromTree(tree: *const Tree, width: f32, height: f32) !Scene {
        return fromTreeWithText(tree, width, height, .{});
    }

    pub fn fromTreeWithText(tree: *const Tree, width: f32, height: f32, text: Text) !Scene {
        return fromTreeWithContext(tree, width, height, text, .{});
    }

    pub fn fromTreeWithContext(tree: *const Tree, width: f32, height: f32, text: Text, host_context: sizing.Context) !Scene {
        var arena = std.heap.ArenaAllocator.init(tree.allocator);
        errdefer arena.deinit();
        const source = try tree.materialize(arena.allocator(), tree.root, 0);
        const root = try generateRoot(arena.allocator(), source);
        var scene = Scene{ .arena = arena, .root = root, .text = text, .length_context = host_context, .viewport = .{ .width = @max(width, 0), .height = @max(height, 0) } };
        scene.length_context.viewport_width = scene.length_context.viewport_width orelse width;
        scene.length_context.viewport_height = scene.length_context.viewport_height orelse height;
        scene.length_context.root_font_size = scene.length_context.root_font_size orelse root.fontSize();
        const vertical = !std.mem.eql(u8, root.style.writingMode, "horizontal-tb");
        scene.length_context.viewport_inline = scene.length_context.viewport_inline orelse if (vertical) height else width;
        scene.length_context.viewport_block = scene.length_context.viewport_block orelse if (vertical) width else height;
        try scene.resolveStyle(root, scene.length_context, width, height, if (std.mem.eql(u8, root.style.writingMode, "horizontal-tb")) width else height);
        try scene.prepareChildren(root, width, height);
        try scene.resolveStyle(root, scene.length_context, width, height, if (vertical) height else width);
        if (!std.mem.eql(u8, source.style.display, "none")) try scene.layout(root, .{ .x = 0, .y = 0, .width = width, .height = height }, null);
        return scene;
    }

    pub fn init(allocator: std.mem.Allocator, json: []const u8, width: f32, height: f32) !Scene {
        return initWithText(allocator, json, width, height, .{});
    }

    pub fn initWithText(allocator: std.mem.Allocator, json: []const u8, width: f32, height: f32, text: Text) !Scene {
        return initWithContext(allocator, json, width, height, text, .{});
    }

    pub fn initWithContext(allocator: std.mem.Allocator, json: []const u8, width: f32, height: f32, text: Text, host_context: sizing.Context) !Scene {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const source = try std.json.parseFromSliceLeaky(Node, a, json, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        const root = try generateRoot(a, source);
        var scene = Scene{ .arena = arena, .root = root, .text = text, .length_context = host_context, .viewport = .{ .width = @max(width, 0), .height = @max(height, 0) } };
        scene.length_context.viewport_width = scene.length_context.viewport_width orelse width;
        scene.length_context.viewport_height = scene.length_context.viewport_height orelse height;
        scene.length_context.root_font_size = scene.length_context.root_font_size orelse root.fontSize();
        const vertical = !std.mem.eql(u8, root.style.writingMode, "horizontal-tb");
        scene.length_context.viewport_inline = scene.length_context.viewport_inline orelse if (vertical) height else width;
        scene.length_context.viewport_block = scene.length_context.viewport_block orelse if (vertical) width else height;
        try scene.resolveStyle(root, scene.length_context, width, height, if (std.mem.eql(u8, root.style.writingMode, "horizontal-tb")) width else height);
        try scene.prepareChildren(root, width, height);
        try scene.resolveStyle(root, scene.length_context, width, height, if (vertical) height else width);
        if (!std.mem.eql(u8, source.style.display, "none")) try scene.layout(root, .{ .x = 0, .y = 0, .width = @max(width, 0), .height = @max(height, 0) }, null);
        return scene;
    }

    pub fn deinit(self: *Scene) void {
        self.arena.deinit();
    }

    /// Measure using a known border-box width before placing descendants.
    pub fn naturalHeightForWidth(self: *const Scene, n: *const Node, border_width: f32) f32 {
        const frame_y = n.padding().vertical() + n.border().vertical();
        const frame_x = n.padding().horizontal() + n.border().horizontal();
        if (n.style.height) |height| return n.constrain(n.borderSize(height, frame_y), false);
        if (n.aspectRatio()) |ratio| {
            const width = n.constrain(border_width, true);
            const basis = if (std.mem.eql(u8, n.style.boxSizing, "content-box")) @max(0, width - frame_x) else width;
            return n.constrain(n.borderSize(basis / ratio, frame_y), false);
        }
        if (std.mem.eql(u8, n.type, "text")) return n.constrain(frame_y + if (n.text.len == 0) @as(f32, 0) else self.text.lineHeight(n.fontSize()), false);
        const inner_width = @max(0, border_width - frame_x);
        const grid = std.mem.eql(u8, n.style.display, "grid");
        const row = std.mem.eql(u8, n.style.display, "flex") and (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        const block = std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "flow-root");
        var total: f32 = 0;
        var previous: f32 = 0;
        var row_height: f32 = 0;
        const count = @max(1, n.style.columns.len);
        var fixed: f32 = 0;
        var fractions: f32 = 0;
        if (grid) for (n.style.columns) |track| {
            if (track >= 0) fixed += track else fractions -= track;
        };
        const free = @max(0, inner_width - fixed - n.style.gap * @as(f32, @floatFromInt(count - 1)));
        for (n.children, 0..) |*child, i| {
            const margins = child.margin();
            const child_frame = child.padding().horizontal() + child.border().horizontal();
            const track = if (grid and n.style.columns.len > 0) n.style.columns[i % count] else @as(f32, -1);
            const available = if (!grid or n.style.columns.len == 0) inner_width else if (track >= 0) track else if (fractions > 0) free * -track / fractions else 0;
            const child_width = child.constrain(if (child.style.width) |value| child.borderSize(value, child_frame) else @max(0, available - margins.horizontal()), true);
            const height = self.naturalHeightForWidth(child, child_width);
            if (grid) {
                row_height = @max(row_height, height + margins.vertical());
                if ((i + 1) % count == 0 or i + 1 == n.children.len) {
                    total += row_height;
                    if (i + 1 < n.children.len) total += n.style.gap;
                    row_height = 0;
                }
            } else if (row) {
                total = @max(total, height + margins.vertical());
            } else if (block) {
                const collapse_top = n.padding().top == 0 and n.border().top == 0 and std.mem.eql(u8, n.style.overflow, "visible") and !std.mem.eql(u8, n.style.display, "flow-root");
                total += if (i == 0) (if (collapse_top) 0 else margins.top) else @import("layout_block.zig").collapsePair(previous, margins.top);
                total += height;
                previous = margins.bottom;
            } else {
                if (i > 0) total += n.style.gap;
                total += height + margins.vertical();
            }
        }
        if (block and n.children.len > 0) total += previous;
        total += frame_y;
        if (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input")) total = @max(total, 44);
        return n.constrain(total, false);
    }

    /// Natural border-box height of a node's own box, excluding its margins.
    ///
    /// Flow layout adds margins itself (with collapsing), so folding them in
    /// here would double count them; callers that need outer size add
    /// `node.margin()` explicitly.
    pub fn naturalHeight(self: *const Scene, n: *const Node) f32 {
        const frame = n.padding().vertical() + n.border().vertical();
        if (n.style.height) |height| return n.constrain(n.borderSize(height, frame), false);
        if (n.style.width) |width| {
            if (n.aspectRatio()) |ratio| {
                const horizontal_frame = n.padding().horizontal() + n.border().horizontal();
                const border_width = n.constrain(n.borderSize(width, horizontal_frame), true);
                const basis = if (std.mem.eql(u8, n.style.boxSizing, "content-box")) @max(0, border_width - horizontal_frame) else border_width;
                return n.constrain(n.borderSize(basis / ratio, frame), false);
            }
        }
        if (std.mem.eql(u8, n.type, "text")) {
            return n.constrain(if (n.text.len == 0) frame else self.text.lineHeight(n.fontSize()) + frame, false);
        }
        var total: f32 = 0;
        if (std.mem.eql(u8, n.style.display, "grid")) {
            const column_count = @max(n.style.columns.len, 1);
            var row_height: f32 = 0;
            for (n.children, 0..) |*child, i| {
                row_height = @max(row_height, self.outerHeight(child));
                if ((i + 1) % column_count == 0 or i + 1 == n.children.len) {
                    total += row_height + (if (i + 1 < n.children.len) n.style.gap else 0);
                    row_height = 0;
                }
            }
            return n.constrain(total + frame, false);
        }
        const is_row = std.mem.eql(u8, n.style.display, "flex") and
            (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        if (is_row) {
            for (n.children) |*child| total = @max(total, self.outerHeight(child));
        } else if (std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "flow-root")) {
            const block = @import("layout_block.zig");
            const collapses_top = n.padding().top == 0 and n.border().top == 0 and std.mem.eql(u8, n.style.overflow, "visible") and !std.mem.eql(u8, n.style.display, "flow-root");
            var previous: f32 = 0;
            for (n.children, 0..) |*child, i| {
                const margins = child.margin();
                total += if (i == 0) (if (collapses_top) 0 else margins.top) else block.collapsePair(previous, margins.top);
                total += self.naturalHeight(child);
                previous = margins.bottom;
            }
            if (n.children.len > 0) total += previous;
        } else {
            for (n.children) |*child| total += self.outerHeight(child);
            if (n.children.len > 1) total += n.style.gap * @as(f32, @floatFromInt(n.children.len - 1));
        }
        total += frame;
        if (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input")) total = @max(total, 44);
        return n.constrain(total, false);
    }

    /// Border box plus vertical margins: what a sibling gap has to accommodate.
    pub fn outerHeight(self: *const Scene, n: *const Node) f32 {
        return self.naturalHeight(n) + n.margin().vertical();
    }

    pub fn layout(self: *Scene, source: *const Node, bounds_in: Rect, parent_id: ?u32) anyerror!void {
        const n = try self.arena.allocator().create(Node);
        n.* = source.*;
        var b = bounds_in;
        const frame_x = n.padding().horizontal() + n.border().horizontal();
        const frame_y = n.padding().vertical() + n.border().vertical();
        if (parent_id == null) {
            if (n.style.width) |width| b.width = n.borderSize(width, frame_x);
            if (n.style.height) |height| b.height = n.borderSize(height, frame_y);
        }
        b.width = n.constrain(b.width, true);
        b.height = n.constrain(b.height, false);
        const parent_is_flex = if (parent_id) |id| if (self.find(id)) |parent| std.mem.eql(u8, parent.node.style.display, "flex") else false else false;
        if (n.aspectRatio()) |ratio| if (!parent_is_flex) {
            const content_sizing = std.mem.eql(u8, n.style.boxSizing, "content-box");
            if (n.style.width != null and n.style.height == null) {
                const basis = if (content_sizing) @max(0, b.width - frame_x) else b.width;
                b.height = n.constrain(n.borderSize(basis / ratio, frame_y), false);
            } else if (n.style.height != null and n.style.width == null) {
                const basis = if (content_sizing) @max(0, b.height - frame_y) else b.height;
                b.width = n.constrain(n.borderSize(basis * ratio, frame_x), true);
            } else if (n.style.width == null and n.style.height == null) {
                const basis = if (content_sizing) @max(0, b.width - frame_x) else b.width;
                b.height = n.constrain(n.borderSize(basis / ratio, frame_y), false);
            }
        };
        const bounds = b;
        const frame_w = n.padding().horizontal() + n.border().horizontal();
        const frame_h = n.padding().vertical() + n.border().vertical();
        try self.prepareChildren(n, @max(0, bounds.width - frame_w), if (parent_id == null or n.style.height != null) @max(0, bounds.height - frame_h) else null);
        try self.index.put(self.arena.allocator(), n.id, self.items.items.len);
        try self.items.append(self.arena.allocator(), .{ .node = n, .bounds = bounds, .parent_id = parent_id });

        const pad = n.padding();
        const bd = n.border();
        const inset_x = pad.horizontal() + bd.horizontal();
        const inner_width = @max(0, bounds.width - inset_x);
        const inner_height = @max(0, bounds.height - (pad.vertical() + bd.vertical()));

        if (std.mem.eql(u8, n.style.display, "grid")) {
            const column_count = @max(n.style.columns.len, 1);
            var fixed: f32 = 0;
            var fractions: f32 = 0;
            for (n.style.columns) |track| {
                if (track >= 0) fixed += track else fractions -= track;
            }
            const free = @max(0, inner_width - fixed - n.style.gap * @as(f32, @floatFromInt(column_count - 1)));
            var x: f32 = 0;
            var y: f32 = 0;
            var row_height: f32 = 0;
            for (n.children, 0..) |*child, i| {
                const column = i % column_count;
                const track = if (n.style.columns.len == 0) -1 else n.style.columns[column];
                const track_width = if (n.style.columns.len == 0) inner_width else if (track >= 0) track else if (fractions > 0) free * -track / fractions else 0;
                const margin = child.margin();
                const frame = child.padding().horizontal() + child.border().horizontal();
                const width = child.constrain(if (child.style.width) |value| child.borderSize(value, frame) else @max(0, track_width - margin.horizontal()), true);
                const height = self.naturalHeightForWidth(child, width);
                try self.layout(child, .{ .x = bounds.x + pad.left + bd.left + x + margin.left, .y = bounds.y + pad.top + bd.top + y + margin.top, .width = width, .height = height }, n.id);
                row_height = @max(row_height, self.find(child.id).?.bounds.height + margin.vertical());
                x += track_width + n.style.gap;
                if (column + 1 == column_count) {
                    x = 0;
                    y += row_height + n.style.gap;
                    row_height = 0;
                }
            }
            return;
        }

        // Block layout (CSS block formatting context)
        if (std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "flow-root")) {
            try @import("layout_block.zig").layout(self, n, bounds, inner_width);
            return;
        }

        // Flexbox layout
        try @import("layout_flex.zig").layout(self, n, bounds, inner_width, inner_height);
    }

    pub fn find(self: *const Scene, id: u32) ?Item {
        const item = self.items.items[self.index.get(id) orelse return null];
        if (std.mem.eql(u8, item.node.type, "__layout_root")) return null;
        return item;
    }

    pub fn clipFor(self: *const Scene, item: Item) Rect {
        var clip = self.viewport;
        var parent_id = item.parent_id;
        while (parent_id) |id| {
            const parent = self.find(id) orelse break;
            const overflow = parent.node.style.overflow;
            if (std.mem.eql(u8, overflow, "hidden") or std.mem.eql(u8, overflow, "clip") or std.mem.eql(u8, overflow, "scroll") or std.mem.eql(u8, overflow, "auto")) {
                clip = clip.intersect(parent.bounds.inset(parent.node.border()));
            }
            parent_id = parent.parent_id;
        }
        return clip;
    }

    fn descendsFrom(self: *const Scene, item: Item, ancestor: u32) bool {
        var parent_id = item.parent_id;
        while (parent_id) |id| {
            if (id == ancestor) return true;
            parent_id = (self.find(id) orelse return false).parent_id;
        }
        return false;
    }

    pub fn applyScroll(self: *Scene, offsets: *std.AutoHashMap(u32, f32)) void {
        for (0..self.items.items.len) |i| {
            const viewport = self.items.items[i];
            if (!std.mem.eql(u8, viewport.node.style.overflow, "scroll") and !std.mem.eql(u8, viewport.node.style.overflow, "auto")) continue;
            var bottom = viewport.bounds.bottom();
            for (self.items.items) |child| {
                if (child.parent_id == viewport.node.id) bottom = @max(bottom, child.bounds.bottom() + child.node.margin().bottom + viewport.node.padding().bottom);
            }
            const maximum = @max(0, bottom - viewport.bounds.bottom());
            const entry = offsets.getPtr(viewport.node.id) orelse continue;
            entry.* = std.math.clamp(entry.*, 0, maximum);
            const offset = entry.*;
            for (self.items.items[i + 1 ..]) |*child| {
                if (self.descendsFrom(child.*, viewport.node.id)) child.bounds.y -= offset;
            }
        }
    }

    pub fn scrollTarget(self: *const Scene, x: f32, y: f32) ?u32 {
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            const item = self.items.items[i];
            if ((std.mem.eql(u8, item.node.style.overflow, "scroll") or std.mem.eql(u8, item.node.style.overflow, "auto")) and item.bounds.contains(x, y) and self.clipFor(item).contains(x, y)) return item.node.id;
        }
        return null;
    }

    pub fn hitTest(self: *const Scene, x: f32, y: f32) ?u32 {
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            const item = self.items.items[i];
            if (item.node.clickable and item.bounds.contains(x, y) and self.clipFor(item).contains(x, y)) return item.node.id;
        }
        return null;
    }
};
