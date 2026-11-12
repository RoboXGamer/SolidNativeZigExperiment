//! Backend-independent retained scene, box model and layout dispatch.
const std = @import("std");
pub const Tree = @import("tree.zig").Tree;

const style_mod = @import("style.zig");
const sizing = @import("sizing.zig");
pub const Style = style_mod.Style;
const transform_mod = @import("transform.zig");

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
    focusable: bool = false,
    tabIndex: ?i32 = null,
    value: []const u8 = "",
    /// Optional input for a future replaced-element measurement provider.
    intrinsicAspectRatio: ?f32 = null,
    style: Style = .{},
    children: []Node = &.{},

    pub fn effectiveOverflowX(self: *const Node) []const u8 {
        if (self.style.overflowX.len > 0) return self.style.overflowX;
        return self.style.overflow;
    }

    pub fn effectiveOverflowY(self: *const Node) []const u8 {
        if (self.style.overflowY.len > 0) return self.style.overflowY;
        return self.style.overflow;
    }

    pub fn isScrollContainerX(self: *const Node) bool {
        const ox = self.effectiveOverflowX();
        return std.mem.eql(u8, ox, "scroll") or std.mem.eql(u8, ox, "auto");
    }

    pub fn isScrollContainerY(self: *const Node) bool {
        const oy = self.effectiveOverflowY();
        return std.mem.eql(u8, oy, "scroll") or std.mem.eql(u8, oy, "auto");
    }

    pub fn isScrollContainer(self: *const Node) bool {
        return self.isScrollContainerX() or self.isScrollContainerY();
    }

    pub fn clipsX(self: *const Node) bool {
        const ox = self.effectiveOverflowX();
        return std.mem.eql(u8, ox, "hidden") or std.mem.eql(u8, ox, "clip") or std.mem.eql(u8, ox, "scroll") or std.mem.eql(u8, ox, "auto");
    }

    pub fn clipsY(self: *const Node) bool {
        const oy = self.effectiveOverflowY();
        return std.mem.eql(u8, oy, "hidden") or std.mem.eql(u8, oy, "clip") or std.mem.eql(u8, oy, "scroll") or std.mem.eql(u8, oy, "auto");
    }

    pub fn isPositioned(self: *const Node) bool {
        return !std.mem.eql(u8, self.style.position, "static");
    }

    pub fn isOutOfFlow(self: *const Node) bool {
        return std.mem.eql(u8, self.style.position, "absolute") or std.mem.eql(u8, self.style.position, "fixed");
    }

    pub fn isFocusable(self: *const Node) bool {
        if (!@import("interaction.zig").acceptsFocus(self)) return false;
        if (std.mem.eql(u8, self.type, "input") or std.mem.eql(u8, self.type, "button")) {
            return self.clickable;
        }
        if (self.focusable) return true;
        if (self.tabIndex != null) return true;
        return false;
    }

    pub fn isFocusableForTab(self: *const Node) bool {
        if (!self.isFocusable()) return false;
        if (self.tabIndex) |ti| return ti >= 0;
        return true;
    }

    /// Padding ring; controls provide a default which author values override.
    pub fn padding(self: *const Node) Edges {
        const default: f32 = if (std.mem.eql(u8, self.type, "button") or std.mem.eql(u8, self.type, "input") or std.mem.eql(u8, self.type, "select") or std.mem.eql(u8, self.type, "option")) 10 else 0;
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

    pub fn textContext(self: *const Node, base: Text) Text {
        var result = base;
        result.typography = .{
            .font_family = self.style.fontFamily,
            .font_weight = self.style.fontWeight,
            .font_style = self.style.fontStyle,
            .language = self.style.language,
            .text_transform = self.style.textTransform,
            .letter_spacing = self.style.letterSpacing orelse 0,
            .word_spacing = self.style.wordSpacing orelse 0,
            .tab_size = self.style.tabSize,
            .tab_size_is_length = if (self.style.tabSizeCss) |css| std.mem.eql(u8, css, "length") else false,
            .text_indent = self.style.textIndent orelse 0,
            .ruby_align = self.style.rubyAlign,
        };
        return result;
    }

    /// Paint projection only: original text and editing/selection offsets survive.
    pub fn shapeText(self: *const Node, base: Text, a: std.mem.Allocator, available: f32) ![]text_mod.ShapedLine {
        const text = self.textContext(base);
        const lines = try text.shapeLines(a, self.text, self.fontSize(), available, self.style.whiteSpace);
        for (lines, 0..) |*line, i| {
            const capacity = @max(0, available - line.indent);
            if (self.clipsX() and std.mem.eql(u8, self.style.textOverflow, "ellipsis") and (std.mem.eql(u8, self.style.whiteSpace, "nowrap") or std.mem.eql(u8, self.style.whiteSpace, "pre"))) {
                line.text = try text.ellipsize(a, line.text, self.fontSize(), capacity);
                line.width = text.width(line.text, self.fontSize());
            }
            const alignment = if (i + 1 == lines.len and !std.mem.eql(u8, self.style.textAlignLast, "auto")) self.style.textAlignLast else self.style.textAlign;
            const free = @max(0, capacity - line.width);
            const rtl = std.mem.eql(u8, self.style.direction, "rtl");
            line.offset_x = line.indent + if (std.mem.eql(u8, alignment, "center")) free / 2 else if (std.mem.eql(u8, alignment, "right") or (std.mem.eql(u8, alignment, "end") and !rtl) or (std.mem.eql(u8, alignment, "start") and rtl)) free else @as(f32, 0);
        }
        return lines;
    }

    pub fn aspectRatio(self: *const Node) ?f32 {
        const value = self.style.aspectRatio orelse self.intrinsicAspectRatio orelse return null;
        return if (std.math.isFinite(value) and value > 0) value else null;
    }

    pub fn mainGap(self: *const Node, is_row: bool) f32 {
        const gap_val = if (is_row) self.style.columnGap else self.style.rowGap;
        return gap_val orelse self.style.gap;
    }

    pub fn crossGap(self: *const Node, is_row: bool) f32 {
        const gap_val = if (is_row) self.style.rowGap else self.style.columnGap;
        return gap_val orelse self.style.gap;
    }
};

pub const Item = struct {
    node: *const Node,
    bounds: Rect,
    parent_id: ?u32 = null,
    used_margin: Edges = .{},

    pub fn marginBox(self: Item) Rect {
        return self.bounds.outset(self.used_margin);
    }
};

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
        !std.mem.eql(u8, display, "flex") and !std.mem.eql(u8, display, "inline-flex") and
        !std.mem.eql(u8, display, "grid") and !std.mem.eql(u8, display, "inline") and
        !std.mem.eql(u8, display, "inline-block")) return error.UnsupportedDisplay;
    var children: std.ArrayList(Node) = .empty;
    for (source.children) |child| try appendGenerated(a, &children, child);
    var copy = source;
    if (std.mem.eql(u8, copy.type, "text") and (std.mem.eql(u8, copy.style.whiteSpace, "normal") or std.mem.eql(u8, copy.style.whiteSpace, "nowrap"))) copy.text = try text_mod.collapseWhitespace(a, copy.text);
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

pub const ScrollOffset = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const ScrollExtent = struct {
    max_scroll_x: f32 = 0,
    max_scroll_y: f32 = 0,
    total_width: f32 = 0,
    total_height: f32 = 0,
};

pub const Scene = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node,
    items: std.ArrayList(Item) = .empty,
    index: std.AutoHashMapUnmanaged(u32, usize) = .empty,
    /// Backend text metrics; defaults to the headless estimator.
    text: Text = .{},
    length_context: sizing.Context = .{},
    viewport: Rect = .{},

    pub fn textFor(self: *const Scene, node: *const Node) Text {
        return node.textContext(self.text);
    }

    fn intrinsicWidth(self: *const Scene, n: *const Node, minimum: bool) f32 {
        const frame = n.padding().horizontal() + n.border().horizontal();
        if (std.mem.eql(u8, n.type, "text")) return frame + if (minimum) self.textFor(n).minContentWidth(n.text, n.fontSize()) else self.textFor(n).maxContentWidth(n.text, n.fontSize());
        if (std.mem.eql(u8, n.type, "select") and n.children.len == 0) {
            const display_text = if (n.text.len > 0) n.text else n.value;
            const text_w = if (minimum) self.textFor(n).minContentWidth(display_text, n.fontSize()) else self.textFor(n).maxContentWidth(display_text, n.fontSize());
            return frame + text_w + self.textFor(n).maxContentWidth(" v", n.fontSize());
        }
        const is_flex = std.mem.eql(u8, n.style.display, "flex") or std.mem.eql(u8, n.style.display, "inline-flex");
        const row = is_flex and (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        var width: f32 = 0;
        var in_flow_seen: usize = 0;
        for (n.children) |*child| {
            if (child.isOutOfFlow()) continue;
            const child_frame = child.padding().horizontal() + child.border().horizontal();
            const contribution = if (child.style.width) |v| child.constrain(child.borderSize(v, child_frame), true) else child.constrain(self.intrinsicWidth(child, minimum), true);
            const child_width = contribution + child.margin().horizontal();
            if (row) {
                if (in_flow_seen > 0) width += n.style.gap;
                width += child_width;
            } else width = @max(width, child_width);
            in_flow_seen += 1;
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
        if (std.mem.eql(u8, n.type, "text")) {
            if (n.text.len == 0) return frame;
            const line_h = if (n.style.lineHeight) |lh| (if (lh > 0) lh else self.textFor(n).lineHeight(n.fontSize())) else self.textFor(n).lineHeight(n.fontSize());
            var lines: usize = 1;
            for (n.text) |ch| if (ch == '\n') {
                lines += 1;
            };
            return frame + @as(f32, @floatFromInt(lines)) * line_h;
        }
        if (std.mem.eql(u8, n.type, "select") and n.children.len == 0) {
            return frame + self.textFor(n).lineHeight(n.fontSize());
        }
        const is_flex = std.mem.eql(u8, n.style.display, "flex") or std.mem.eql(u8, n.style.display, "inline-flex");
        const row = is_flex and (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        var height: f32 = 0;
        var in_flow_seen: usize = 0;
        for (n.children) |*child| {
            if (child.isOutOfFlow()) continue;
            const child_frame = child.padding().vertical() + child.border().vertical();
            const contribution = if (child.style.height) |v| child.constrain(child.borderSize(v, child_frame), false) else child.constrain(self.intrinsicHeight(child), false);
            const child_height = contribution + child.margin().vertical();
            if (row) height = @max(height, child_height) else {
                if (in_flow_seen > 0 and is_flex) height += n.style.gap;
                height += child_height;
            }
            in_flow_seen += 1;
        }
        return height + frame;
    }

    fn resolveStyle(self: *const Scene, n: *Node, context: sizing.Context, containing_width: ?f32, containing_height: ?f32, inline_size: ?f32) !void {
        if (n.style.fontSizeCss) |css| {
            var font_context = context;
            font_context.font_size = context.font_size orelse text_mod.default_font_size;
            font_context.percentage = font_context.font_size;
            const keyword_size = text_mod.fontSizeKeyword(css, font_context.font_size.?);
            const used: sizing.Resolution = if (keyword_size) |value| .{ .length = value } else try sizing.resolve(css, font_context);
            n.style.fontSize = switch (used) {
                .length => |v| if (v > 0) v else return error.InvalidFontSize,
                else => return error.InvalidFontSize,
            };
            n.style.fontSizeCss = null;
        }
        if (n.style.fontWeightCss) |css| {
            if (std.ascii.eqlIgnoreCase(css, "normal")) n.style.fontWeight = 400 else if (std.ascii.eqlIgnoreCase(css, "bold")) n.style.fontWeight = 700 else if (std.ascii.eqlIgnoreCase(css, "bolder")) n.style.fontWeight = if (n.style.fontWeight < 350) 400 else if (n.style.fontWeight < 550) 700 else 900 else if (std.ascii.eqlIgnoreCase(css, "lighter")) n.style.fontWeight = if (n.style.fontWeight < 550) 100 else if (n.style.fontWeight < 750) 400 else 700 else n.style.fontWeight = std.fmt.parseFloat(f32, css) catch return error.InvalidFontWeight;
            n.style.fontWeightCss = null;
        }
        if (!std.math.isFinite(n.style.fontWeight) or n.style.fontWeight < 1 or n.style.fontWeight > 1000) return error.InvalidFontWeight;
        if (!std.ascii.eqlIgnoreCase(n.style.fontStyle, "normal") and !std.ascii.eqlIgnoreCase(n.style.fontStyle, "italic") and !std.ascii.startsWithIgnoreCase(n.style.fontStyle, "oblique")) return error.InvalidFontStyle;
        inline for (.{ "letterSpacing", "wordSpacing", "textIndent" }) |field| {
            if (@field(n.style, field ++ "Css")) |css| {
                if (std.ascii.eqlIgnoreCase(css, "normal") and !std.mem.eql(u8, field, "textIndent")) {
                    @field(n.style, field) = 0;
                } else {
                    if (std.mem.eql(u8, field, "letterSpacing") and std.mem.indexOfScalar(u8, css, '%') != null) return error.InvalidLength;
                    var ctx = context;
                    ctx.font_size = n.fontSize();
                    ctx.percentage = if (std.mem.eql(u8, field, "textIndent")) inline_size else n.fontSize();
                    @field(n.style, field) = switch (try sizing.resolve(css, ctx)) {
                        .length => |v| v,
                        else => return error.InvalidLength,
                    };
                }
                @field(n.style, field ++ "Css") = null;
            }
            if (@field(n.style, field)) |v| if (!std.math.isFinite(v)) return error.InvalidLength;
        }
        if (n.style.tabSizeCss) |css| if (!std.mem.eql(u8, css, "length")) {
            if (std.fmt.parseFloat(f32, css)) |number| {
                n.style.tabSize = number;
                n.style.tabSizeCss = null;
            } else |_| {
                if (std.mem.indexOfScalar(u8, css, '%') != null) return error.InvalidLength;
                var ctx = context;
                ctx.font_size = n.fontSize();
                n.style.tabSize = switch (try sizing.resolve(css, ctx)) {
                    .length => |v| v,
                    else => return error.InvalidLength,
                };
                n.style.tabSizeCss = "length";
            }
        };
        if (!std.math.isFinite(n.style.tabSize) or n.style.tabSize < 0) return error.InvalidLength;
        inline for (.{ "textTransform", "textOverflow", "textAlignLast" }) |field| {
            var valid = false;
            inline for (.{ "none", "uppercase", "lowercase", "capitalize", "full-width", "clip", "ellipsis", "auto", "left", "right", "center", "start", "end", "justify" }) |value| {
                const allowed = if (comptime std.mem.eql(u8, field, "textTransform")) std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "uppercase") or std.mem.eql(u8, value, "lowercase") or std.mem.eql(u8, value, "capitalize") or std.mem.eql(u8, value, "full-width") else if (comptime std.mem.eql(u8, field, "textOverflow")) std.mem.eql(u8, value, "clip") or std.mem.eql(u8, value, "ellipsis") else std.mem.eql(u8, value, "auto") or std.mem.eql(u8, value, "left") or std.mem.eql(u8, value, "right") or std.mem.eql(u8, value, "center") or std.mem.eql(u8, value, "start") or std.mem.eql(u8, value, "end") or std.mem.eql(u8, value, "justify");
                if (allowed and std.ascii.eqlIgnoreCase(@field(n.style, field), value)) {
                    @field(n.style, field) = value;
                    valid = true;
                }
            }
            if (!valid) return error.InvalidTypography;
        }
        var valid_ruby_align = false;
        inline for (.{ "start", "center", "space-between", "space-around" }) |val| {
            if (std.ascii.eqlIgnoreCase(n.style.rubyAlign, val)) {
                n.style.rubyAlign = val;
                valid_ruby_align = true;
            }
        }
        if (!valid_ruby_align) return error.InvalidTypography;
        if (std.ascii.eqlIgnoreCase(n.style.isolation, "auto")) n.style.isolation = "auto" else if (std.ascii.eqlIgnoreCase(n.style.isolation, "isolate")) n.style.isolation = "isolate" else return error.InvalidIsolation;
        var valid_position = false;
        inline for (.{ "static", "relative", "absolute", "fixed", "sticky" }) |position| if (std.ascii.eqlIgnoreCase(n.style.position, position)) {
            n.style.position = position;
            valid_position = true;
        };
        if (!valid_position) return error.InvalidPosition;
        if (n.style.opacityCss) |css| {
            var ctx = context;
            ctx.percentage = 1;
            ctx.font_size = n.fontSize();
            n.style.opacity = (try sizing.resolveNumber(css, ctx)) orelse return error.UnresolvedLengthContext;
        }
        if (std.math.isNan(n.style.opacity)) n.style.opacity = 0;
        n.style.opacity = std.math.clamp(n.style.opacity, 0, 1);
        if (!std.mem.eql(u8, n.style.boxSizing, "content-box") and !std.mem.eql(u8, n.style.boxSizing, "border-box")) return error.InvalidBoxSizing;
        inline for (.{ "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "marginTop", "marginRight", "marginBottom", "marginLeft", "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "rowGap", "columnGap", "lineHeight", "top", "right", "bottom", "left" }) |name| {
            const is_inset = std.mem.eql(u8, name, "top") or std.mem.eql(u8, name, "right") or std.mem.eql(u8, name, "bottom") or std.mem.eql(u8, name, "left");
            const allow_negative = std.mem.startsWith(u8, name, "margin") or is_inset;
            if (@field(n.style, name)) |number| {
                if (!std.math.isFinite(number) or (number < 0 and !allow_negative)) return error.InvalidLength;
            }
            if ((!is_inset or n.isPositioned()) and (if (@field(n.style, name ++ "Css")) |value| value.len > 0 else false)) {
                const css = @field(n.style, name ++ "Css").?;
                // Older bridge snapshots encoded an absent optional CSS value as "".

                if (std.mem.startsWith(u8, name, "border") and std.mem.indexOfScalar(u8, css, '%') != null) return error.InvalidLength;
                var ctx = context;
                ctx.font_size = n.fontSize();
                ctx.percentage = if (std.mem.eql(u8, name, "height") or std.mem.eql(u8, name, "minHeight") or std.mem.eql(u8, name, "maxHeight") or std.mem.eql(u8, name, "rowGap") or std.mem.eql(u8, name, "top") or std.mem.eql(u8, name, "bottom")) containing_height else if (std.mem.eql(u8, name, "width") or std.mem.eql(u8, name, "minWidth") or std.mem.eql(u8, name, "maxWidth") or std.mem.eql(u8, name, "columnGap") or std.mem.eql(u8, name, "left") or std.mem.eql(u8, name, "right")) containing_width else inline_size;
                if (std.mem.eql(u8, name, "lineHeight")) ctx.percentage = n.fontSize();
                const is_fit_function = std.mem.startsWith(u8, css, "fit-content(") and std.mem.endsWith(u8, css, ")");
                const value: sizing.Resolution = if (is_fit_function) .{ .keyword = .fit_content } else try sizing.resolve(css, ctx);
                switch (value) {
                    .length => |number| {
                        if (number < 0 and !allow_negative) return error.NegativeSize;
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

    fn colorTokens(self: *Scene, input: []const u8, current: []const u8) ![]const u8 {
        var first: ?usize = null;
        var i: usize = 0;
        while (i + 12 <= input.len) : (i += 1) if (std.ascii.eqlIgnoreCase(input[i .. i + 12], "currentColor")) {
            first = i;
            break;
        };
        if (first == null) return input;
        var out: std.ArrayList(u8) = .empty;
        i = 0;
        while (i < input.len) {
            if (i + 12 <= input.len and std.ascii.eqlIgnoreCase(input[i .. i + 12], "currentColor")) {
                try out.appendSlice(self.arena.allocator(), current);
                i += 12;
            } else {
                try out.append(self.arena.allocator(), input[i]);
                i += 1;
            }
        }
        return out.toOwnedSlice(self.arena.allocator());
    }
    fn inheritComputedStyle(self: *Scene, child: *Node, parent: *const Node) void {
        if (child.style.fontSize == 0 and child.style.fontSizeCss == null) child.style.fontSize = parent.fontSize();
        inline for (.{ "fontFamily", "fontWeight", "fontStyle", "language", "letterSpacing", "wordSpacing", "tabSize", "textTransform", "textAlignLast", "textIndent", "rubyAlign" }, 0..) |field, bit| {
            const defaults: Style = .{};
            const at_default = if (comptime @TypeOf(@field(child.style, field)) == []const u8) std.mem.eql(u8, @field(child.style, field), @field(defaults, field)) else @field(child.style, field) == @field(defaults, field);
            if (child.style.typographySpecified & (@as(u32, 1) << bit) == 0 and at_default) {
                @field(child.style, field) = @field(parent.style, field);
                if (comptime std.mem.eql(u8, field, "tabSize")) child.style.tabSizeCss = parent.style.tabSizeCss;
            }
        }
        // Relative weight keywords resolve against the parent's computed weight.
        if (child.style.fontWeightCss) |css| if (std.ascii.eqlIgnoreCase(css, "bolder") or std.ascii.eqlIgnoreCase(css, "lighter")) {
            child.style.fontWeight = parent.style.fontWeight;
        };
        inline for (.{ "visibility", "pointerEvents", "cursor" }, 0..) |field, bit| if (child.style.interactionSpecified & (@as(u32, 1) << bit) == 0 and std.mem.eql(u8, @field(child.style, field), @field(@as(Style, .{}), field))) {
            @field(child.style, field) = @field(parent.style, field);
        };
        if (child.style.color.len == 0 or std.ascii.eqlIgnoreCase(child.style.color, "currentColor")) child.style.color = if (parent.style.color.len > 0) parent.style.color else "#ffffff";
        inline for (.{ "backgroundColor", "borderColor", "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor", "outlineColor", "backgroundGradient", "boxShadow" }) |field| {
            @field(child.style, field) = self.colorTokens(@field(child.style, field), child.style.color) catch @field(child.style, field);
        }
        if (child.style.borderColor.len == 0) child.style.borderColor = child.style.color;
        if (child.style.outlineColor.len == 0) child.style.outlineColor = child.style.color;
    }

    fn prepareChildren(self: *Scene, n: *Node, width: f32, height: ?f32) anyerror!void {
        n.children = try self.arena.allocator().dupe(Node, n.children);
        for (n.children) |*child| {
            if (child.isOutOfFlow()) continue;
            const vertical = !std.mem.eql(u8, n.style.writingMode, "horizontal-tb");
            const inline_size: ?f32 = if (vertical) height else width;
            self.inheritComputedStyle(child, n);
            if (std.mem.eql(u8, child.type, "text") and std.mem.eql(u8, n.style.textOverflow, "ellipsis") and n.clipsX()) {
                child.style.textOverflow = "ellipsis";
                child.style.overflowX = "clip";
            }
            var child_context = self.length_context;
            child_context.font_size = n.fontSize();
            child_context.line_height = if (n.style.lineHeight) |h| (if (h > 0) h else self.textFor(n).lineHeight(n.fontSize())) else self.textFor(n).lineHeight(n.fontSize());
            child_context.root_font_size = self.length_context.root_font_size;
            child_context.root_line_height = self.length_context.root_line_height;
            try self.resolveStyle(child, child_context, width, height, inline_size);
            if (child.style.flexBasisCss) |css| {
                const trimmed = std.mem.trim(u8, css, " \t\r\n");
                if (std.mem.eql(u8, trimmed, "content")) {
                    child.style.flexBasisContent = true;
                    child.style.flexBasis = null;
                } else if (std.mem.eql(u8, trimmed, "auto")) {
                    child.style.flexBasis = null;
                } else if (std.mem.eql(u8, trimmed, "max-content") or std.mem.eql(u8, trimmed, "min-content") or std.mem.eql(u8, trimmed, "fit-content")) {
                    child.style.flexBasis = null;
                } else {
                    var context = self.length_context;
                    context.font_size = child.fontSize();
                    const row = std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
                    context.percentage = if (row) width else height;
                    switch (try sizing.resolve(css, context)) {
                        .length => |value| {
                            if (value < 0) return error.NegativeSize;
                            child.style.flexBasis = value;
                        },
                        .keyword => |kw| {
                            switch (kw) {
                                .auto => child.style.flexBasis = null,
                                .min_content, .max_content, .fit_content => child.style.flexBasis = null,
                                else => return error.UnsupportedSizingKeyword,
                            }
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
                    }
                }
            }
            const frame_w = child.padding().horizontal() + child.border().horizontal();
            const frame_h = child.padding().vertical() + child.border().vertical();
            var child_w = child.constrain(if (child.style.width) |v| child.borderSize(v, frame_w) else @max(0, width - child.margin().horizontal()), true);
            const child_h: ?f32 = if (child.style.height) |v| child.constrain(child.borderSize(v, frame_h), false) else null;
            if (child.style.width == null) if (child_h) |h| if (child.aspectRatio()) |ratio| {
                const basis = if (std.mem.eql(u8, child.style.boxSizing, "content-box")) @max(0, h - frame_h) else h;
                child_w = child.constrain(child.borderSize(basis * ratio, frame_w), true);
            };
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
        const root_default_lh = scene.textFor(root).lineHeight(root.fontSize());
        const root_lh = if (root.style.lineHeight) |h| (if (h > 0) h else root_default_lh) else root_default_lh;
        scene.length_context.root_line_height = scene.length_context.root_line_height orelse root_lh;
        const vertical = !std.mem.eql(u8, root.style.writingMode, "horizontal-tb");
        scene.length_context.viewport_inline = scene.length_context.viewport_inline orelse if (vertical) height else width;
        scene.length_context.viewport_block = scene.length_context.viewport_block orelse if (vertical) width else height;
        try scene.resolveStyle(root, scene.length_context, width, height, if (std.mem.eql(u8, root.style.writingMode, "horizontal-tb")) width else height);
        scene.length_context.root_font_size = host_context.root_font_size orelse root.fontSize();
        const resolved_root_lh = if (root.style.lineHeight) |h| (if (h > 0) h else scene.textFor(root).lineHeight(root.fontSize())) else scene.textFor(root).lineHeight(root.fontSize());
        scene.length_context.root_line_height = host_context.root_line_height orelse resolved_root_lh;
        scene.inheritComputedStyle(root, root);
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
        const init_root_default_lh = scene.textFor(root).lineHeight(root.fontSize());
        const init_root_lh = if (root.style.lineHeight) |h| (if (h > 0) h else init_root_default_lh) else init_root_default_lh;
        scene.length_context.root_line_height = scene.length_context.root_line_height orelse init_root_lh;
        const vertical = !std.mem.eql(u8, root.style.writingMode, "horizontal-tb");
        scene.length_context.viewport_inline = scene.length_context.viewport_inline orelse if (vertical) height else width;
        scene.length_context.viewport_block = scene.length_context.viewport_block orelse if (vertical) width else height;
        try scene.resolveStyle(root, scene.length_context, width, height, if (std.mem.eql(u8, root.style.writingMode, "horizontal-tb")) width else height);
        scene.length_context.root_font_size = host_context.root_font_size orelse root.fontSize();
        const init_resolved_root_lh = if (root.style.lineHeight) |h| (if (h > 0) h else scene.textFor(root).lineHeight(root.fontSize())) else scene.textFor(root).lineHeight(root.fontSize());
        scene.length_context.root_line_height = host_context.root_line_height orelse init_resolved_root_lh;
        scene.inheritComputedStyle(root, root);
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
        if (std.mem.eql(u8, n.type, "text")) {
            if (n.text.len == 0) return n.constrain(frame_y, false);
            const lh = if (n.style.lineHeight) |h| (if (h > 0) h else self.textFor(n).lineHeight(n.fontSize())) else self.textFor(n).lineHeight(n.fontSize());
            if (!std.mem.eql(u8, n.style.whiteSpace, "nowrap")) {
                const lines = self.textFor(n).wrapWithWhitespace(n.text, n.fontSize(), @max(0, border_width - frame_x), n.style.whiteSpace);
                return n.constrain(frame_y + @as(f32, @floatFromInt(lines.lines)) * lh, false);
            }
            return n.constrain(frame_y + lh, false);
        }
        const inner_width = @max(0, border_width - frame_x);
        const grid = std.mem.eql(u8, n.style.display, "grid");
        if (grid) return n.constrain(frame_y + (@import("layout_grid.zig").measureHeight(self, n, inner_width) catch 0), false);
        const row = std.mem.eql(u8, n.style.display, "flex") and (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        const block = std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "flow-root");
        var total: f32 = 0;
        var row_height: f32 = 0;
        const count = @max(1, n.style.columns.len);
        var fixed: f32 = 0;
        var fractions: f32 = 0;
        if (grid) for (n.style.columns) |track| {
            if (track >= 0) fixed += track else fractions -= track;
        };
        const free = @max(0, inner_width - fixed - n.style.gap * @as(f32, @floatFromInt(count - 1)));
        if (block) {
            const block_output = @import("layout_block.zig").computeBlockLayout(self, n, inner_width, null);
            total = block_output.consumed_height;
        } else {
            var in_flow_seen: usize = 0;
            for (n.children, 0..) |*child, i| {
                if (child.isOutOfFlow()) continue;
                const margins = child.margin();
                const child_frame = child.padding().horizontal() + child.border().horizontal();
                const track = if (grid and n.style.columns.len > 0) n.style.columns[i % count] else @as(f32, -1);
                const available = if (!grid or n.style.columns.len == 0) inner_width else if (track >= 0) track else if (fractions > 0) free * -track / fractions else 0;
                var child_width = child.constrain(if (child.style.width) |value| child.borderSize(value, child_frame) else @max(0, available - margins.horizontal()), true);
                if (child.style.width == null) if (child.style.height) |preferred_height| if (child.aspectRatio()) |ratio| {
                    const child_frame_y = child.padding().vertical() + child.border().vertical();
                    const child_height = child.constrain(child.borderSize(preferred_height, child_frame_y), false);
                    const basis = if (std.mem.eql(u8, child.style.boxSizing, "content-box")) @max(0, child_height - child_frame_y) else child_height;
                    child_width = child.constrain(child.borderSize(basis * ratio, child_frame), true);
                };
                const height = self.naturalHeightForWidth(child, child_width);
                if (grid) {
                    row_height = @max(row_height, height + margins.vertical());
                    if ((in_flow_seen + 1) % count == 0 or in_flow_seen + 1 == n.children.len) {
                        total += row_height;
                        if (in_flow_seen + 1 < n.children.len) total += n.style.gap;
                        row_height = 0;
                    }
                } else if (row) {
                    total = @max(total, height + margins.vertical());
                } else {
                    if (in_flow_seen > 0) total += n.style.gap;
                    total += height + margins.vertical();
                }
                in_flow_seen += 1;
            }
        }
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
            if (n.text.len == 0) return n.constrain(frame, false);
            const lh = if (n.style.lineHeight) |h| (if (h > 0) h else self.textFor(n).lineHeight(n.fontSize())) else self.textFor(n).lineHeight(n.fontSize());
            if (n.style.width) |width| {
                if (!std.mem.eql(u8, n.style.whiteSpace, "nowrap")) {
                    const horizontal_frame = n.padding().horizontal() + n.border().horizontal();
                    const inner_w = @max(0, n.constrain(n.borderSize(width, horizontal_frame), true) - horizontal_frame);
                    const lines = self.textFor(n).wrapWithWhitespace(n.text, n.fontSize(), inner_w, n.style.whiteSpace);
                    return n.constrain(frame + @as(f32, @floatFromInt(lines.lines)) * lh, false);
                }
            }
            return n.constrain(frame + lh, false);
        }
        var total: f32 = 0;
        if (std.mem.eql(u8, n.style.display, "grid")) {
            const column_count = @max(n.style.columns.len, 1);
            var row_height: f32 = 0;
            var in_flow_seen: usize = 0;
            for (n.children) |*child| {
                if (child.isOutOfFlow()) continue;
                row_height = @max(row_height, self.outerHeight(child));
                in_flow_seen += 1;
                if (in_flow_seen % column_count == 0) {
                    total += row_height + n.style.gap;
                    row_height = 0;
                }
            }
            if (row_height > 0) total += row_height;
            return n.constrain(total + frame, false);
        }
        const is_row = std.mem.eql(u8, n.style.display, "flex") and
            (std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse"));
        if (is_row) {
            for (n.children) |*child| {
                if (child.isOutOfFlow()) continue;
                total = @max(total, self.outerHeight(child));
            }
        } else if (std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "flow-root")) {
            const block_output = @import("layout_block.zig").computeBlockLayout(self, n, 0, null);
            total = block_output.consumed_height;
        } else {
            var in_flow_seen: usize = 0;
            for (n.children) |*child| {
                if (child.isOutOfFlow()) continue;
                total += self.outerHeight(child);
                in_flow_seen += 1;
            }
            if (in_flow_seen > 1) total += n.style.gap * @as(f32, @floatFromInt(in_flow_seen - 1));
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
        if (std.mem.eql(u8, n.style.position, "relative")) {
            const rtl = std.mem.eql(u8, n.style.direction, "rtl");
            const dx = if (n.style.left != null and n.style.right != null) (if (rtl) -n.style.right.? else n.style.left.?) else if (n.style.left) |l| l else if (n.style.right) |r| -r else 0;
            const dy = if (n.style.top != null and n.style.bottom != null) n.style.top.? else if (n.style.top) |t| t else if (n.style.bottom) |btm| -btm else 0;
            b.x += dx;
            b.y += dy;
        }
        const bounds = b;
        const frame_w = n.padding().horizontal() + n.border().horizontal();
        const frame_h = n.padding().vertical() + n.border().vertical();
        try self.prepareChildren(n, @max(0, bounds.width - frame_w), if (parent_id == null or n.style.height != null) @max(0, bounds.height - frame_h) else null);
        try self.index.put(self.arena.allocator(), n.id, self.items.items.len);
        try self.items.append(self.arena.allocator(), .{ .node = n, .bounds = bounds, .parent_id = parent_id, .used_margin = n.margin() });

        const pad = n.padding();
        const bd = n.border();
        const inset_x = pad.horizontal() + bd.horizontal();
        const inner_width = @max(0, bounds.width - inset_x);
        const inner_height = @max(0, bounds.height - (pad.vertical() + bd.vertical()));

        if (std.mem.eql(u8, n.style.display, "grid")) {
            try @import("layout_grid.zig").layout(self, n, bounds, inner_width, inner_height);
        } else if (std.mem.eql(u8, n.style.display, "block") or std.mem.eql(u8, n.style.display, "flow-root")) {
            try @import("layout_block.zig").layout(self, n, bounds, inner_width);
        } else {
            // Flexbox layout
            try @import("layout_flex.zig").layout(self, n, bounds, inner_width, inner_height);
        }

        try self.layoutOutOfFlowChildren(n, bounds);
    }

    pub fn findContainingBlock(self: *const Scene, child: *const Node, parent_item: Item) Rect {
        const fixed = std.mem.eql(u8, child.style.position, "fixed");
        var cur_item = parent_item;
        while (true) {
            const transformed = cur_item.node.style.transform.len > 0 and !std.mem.eql(u8, cur_item.node.style.transform, "none");
            if (transformed or (!fixed and cur_item.node.isPositioned())) {
                return cur_item.node.paddingBox(cur_item.bounds);
            }
            if (cur_item.parent_id) |pid| {
                cur_item = self.find(pid) orelse return self.viewport;
            } else {
                return self.viewport;
            }
        }
    }

    pub fn layoutOutOfFlowChildren(self: *Scene, n: *const Node, bounds: Rect) anyerror!void {
        const parent_item = self.find(n.id) orelse Item{ .node = n, .bounds = bounds };
        for (n.children) |*source_child| {
            if (!source_child.isOutOfFlow()) continue;
            const cb = self.findContainingBlock(source_child, parent_item);
            const child = try self.arena.allocator().create(Node);
            child.* = source_child.*;
            try self.resolveStyle(child, self.length_context, cb.width, cb.height, cb.width);
            const child_mg = child.margin();
            const child_frame_x = child.padding().horizontal() + child.border().horizontal();
            const child_frame_y = child.padding().vertical() + child.border().vertical();

            // Sizing
            var w: f32 = undefined;
            if (child.style.width) |specified_w| {
                w = child.constrain(child.borderSize(specified_w, child_frame_x), true);
            } else if (child.style.left != null and child.style.right != null) {
                w = child.constrain(@max(0, cb.width - child.style.left.? - child.style.right.? - child_mg.horizontal()), true);
            } else {
                w = child.constrain(self.intrinsicWidthFor(child, .{ .definite = @max(0, cb.width - child_mg.horizontal()) }), true);
            }

            try self.prepareChildren(child, @max(0, w - child_frame_x), if (child.style.height) |v| @max(0, child.borderSize(v, child_frame_y) - child_frame_y) else null);
            var h: f32 = undefined;
            if (child.style.height) |specified_h| {
                h = child.constrain(child.borderSize(specified_h, child_frame_y), false);
            } else if (child.style.top != null and child.style.bottom != null) {
                h = child.constrain(@max(0, cb.height - child.style.top.? - child.style.bottom.? - child_mg.vertical()), false);
            } else {
                h = child.constrain(self.naturalHeightForWidth(child, w), false);
            }

            // Placement
            var x: f32 = cb.x + child_mg.left;
            if (child.style.left) |left_val| {
                x = cb.x + left_val + child_mg.left;
            } else if (child.style.right) |right_val| {
                x = cb.right() - right_val - w - child_mg.right;
            }

            var y: f32 = cb.y + child_mg.top;
            if (child.style.top) |top_val| {
                y = cb.y + top_val + child_mg.top;
            } else if (child.style.bottom) |bottom_val| {
                y = cb.bottom() - bottom_val - h - child_mg.bottom;
            }

            // Auto margins and self alignment operate in the inset-modified containing block.
            const left = child.style.left orelse 0;
            const right = child.style.right orelse 0;
            const top = child.style.top orelse 0;
            const bottom = child.style.bottom orelse 0;
            const free_x = cb.width - left - right - w - child_mg.horizontal();
            const free_y = cb.height - top - bottom - h - child_mg.vertical();
            if (child.style.left != null and child.style.right != null) {
                if (child.style.marginLeftAuto and child.style.marginRightAuto and free_x > 0) x += free_x / 2 else if (child.style.marginLeftAuto and free_x > 0) x += free_x;
            }
            if (child.style.top != null and child.style.bottom != null) {
                if (child.style.marginTopAuto and child.style.marginBottomAuto and free_y > 0) y += free_y / 2 else if (child.style.marginTopAuto and free_y > 0) y += free_y;
            }
            const justify = child.style.justifySelf;
            const align_self = child.style.alignSelf;
            if (!child.style.marginLeftAuto and !child.style.marginRightAuto) {
                if (std.mem.eql(u8, justify, "center")) x = cb.x + left + free_x / 2 + child_mg.left else if (std.mem.eql(u8, justify, "end") or std.mem.eql(u8, justify, "right")) x = cb.x + left + free_x + child_mg.left;
            }
            if (!child.style.marginTopAuto and !child.style.marginBottomAuto) {
                if (std.mem.eql(u8, align_self, "center")) y = cb.y + top + free_y / 2 + child_mg.top else if (std.mem.eql(u8, align_self, "end") or std.mem.eql(u8, align_self, "flex-end")) y = cb.y + top + free_y + child_mg.top;
            }
            try self.layout(child, .{ .x = x, .y = y, .width = w, .height = h }, n.id);
        }
    }

    pub fn find(self: *const Scene, id: u32) ?Item {
        const item = self.items.items[self.index.get(id) orelse return null];
        if (std.mem.eql(u8, item.node.type, "__layout_root")) return null;
        return item;
    }

    pub fn setUsedMargin(self: *Scene, id: u32, margin: Edges) void {
        const index = self.index.get(id) orelse return;
        self.items.items[index].used_margin = margin;
    }

    pub fn clipFor(self: *const Scene, item: Item) Rect {
        var clip = self.viewport;
        var parent_id = item.parent_id;
        while (parent_id) |id| {
            const parent = self.find(id) orelse break;
            const pbox = parent.bounds.inset(parent.node.border());
            if (parent.node.clipsX()) {
                const new_x = @max(clip.x, pbox.x);
                const right = @min(clip.right(), pbox.right());
                clip.x = new_x;
                clip.width = @max(0, right - new_x);
            }
            if (parent.node.clipsY()) {
                const new_y = @max(clip.y, pbox.y);
                const bottom = @min(clip.bottom(), pbox.bottom());
                clip.y = new_y;
                clip.height = @max(0, bottom - new_y);
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

    pub fn scrollExtent(self: *const Scene, viewport_id: u32) ScrollExtent {
        const viewport = self.find(viewport_id) orelse return .{};
        var max_x = viewport.bounds.right();
        var max_y = viewport.bounds.bottom();

        for (self.items.items) |child| {
            if (child.node.id == viewport_id) continue;
            if (!self.descendsFrom(child, viewport_id)) continue;

            var path_visible = true;
            var cur_parent = child.parent_id;
            while (cur_parent) |pid| {
                if (pid == viewport_id) break;
                if (self.find(pid)) |parent_item| {
                    if (parent_item.node.clipsX() or parent_item.node.clipsY()) {
                        path_visible = false;
                        break;
                    }
                    cur_parent = parent_item.parent_id;
                } else break;
            }

            if (path_visible) {
                const child_bottom = child.bounds.bottom() + child.node.margin().bottom + viewport.node.padding().bottom;
                const child_right = child.bounds.right() + child.node.margin().right + viewport.node.padding().right;
                max_y = @max(max_y, child_bottom);
                max_x = @max(max_x, child_right);
            }
        }

        return .{
            .max_scroll_x = @max(0, max_x - viewport.bounds.right()),
            .max_scroll_y = @max(0, max_y - viewport.bounds.bottom()),
            .total_width = max_x - viewport.bounds.x,
            .total_height = max_y - viewport.bounds.y,
        };
    }

    pub fn applyScrollOffsets(self: *Scene, offsets: *std.AutoHashMap(u32, ScrollOffset)) void {
        const a = self.arena.allocator();
        const original = a.alloc(Rect, self.items.items.len) catch return;
        for (self.items.items, 0..) |item, i| original[i] = item.bounds;
        // Clamp while all geometry is still in the unscrolled coordinate space.
        for (self.items.items) |item| if (offsets.getPtr(item.node.id)) |off| {
            const extent = self.scrollExtent(item.node.id);
            off.x = if (item.node.isScrollContainerX()) std.math.clamp(off.x, 0, extent.max_scroll_x) else 0;
            off.y = if (item.node.isScrollContainerY()) std.math.clamp(off.y, 0, extent.max_scroll_y) else 0;
        };
        for (self.items.items, 0..) |*item, i| {
            var dx: f32 = 0;
            var dy: f32 = 0;
            var parent = item.parent_id;
            var fixed = std.mem.eql(u8, item.node.style.position, "fixed");
            while (parent) |pid| {
                const index = self.index.get(pid) orelse break;
                const p = self.items.items[index];
                if (fixed) {
                    if (p.node.style.transform.len > 0 and !std.mem.eql(u8, p.node.style.transform, "none")) fixed = false;
                } else if (offsets.get(pid)) |off| {
                    dx -= off.x;
                    dy -= off.y;
                }
                // A fixed subtree must stay together; ancestors outside it cannot scroll its descendants.
                if (std.mem.eql(u8, p.node.style.position, "fixed")) fixed = true;
                parent = p.parent_id;
            }
            item.bounds.x = original[i].x + dx;
            item.bounds.y = original[i].y + dy;
        }
        // Sticky translations propagate to all descendants exactly once.
        for (0..self.items.items.len) |i| {
            const item = self.items.items[i];
            if (!std.mem.eql(u8, item.node.style.position, "sticky")) continue;
            var port = self.viewport;
            var parent = item.parent_id;
            while (parent) |pid| {
                const p = self.find(pid) orelse break;
                if (p.node.isScrollContainer() or std.mem.eql(u8, p.node.effectiveOverflowX(), "hidden") or std.mem.eql(u8, p.node.effectiveOverflowY(), "hidden")) {
                    port = p.node.paddingBox(p.bounds);
                    break;
                }
                parent = p.parent_id;
            }
            var target = item.bounds;
            if (item.node.style.top) |v| target.y = @max(target.y, port.y + v);
            if (item.node.style.bottom) |v| target.y = @min(target.y, port.bottom() - v - target.height);
            if (item.node.style.left) |v| target.x = @max(target.x, port.x + v);
            if (item.node.style.right) |v| target.x = @min(target.x, port.right() - v - target.width);
            if (item.parent_id) |pid| if (self.find(pid)) |p| {
                const box = p.node.contentBox(p.bounds);
                target.x = @max(item.bounds.x, @min(target.x, box.right() - target.width));
                target.y = @max(item.bounds.y, @min(target.y, box.bottom() - target.height));
            };
            const dx = target.x - item.bounds.x;
            const dy = target.y - item.bounds.y;
            self.items.items[i].bounds = target;
            for (self.items.items[i + 1 ..]) |*child| if (self.descendsFrom(child.*, item.node.id)) {
                child.bounds.x += dx;
                child.bounds.y += dy;
            };
        }
    }

    pub fn applyScroll(self: *Scene, offsets: *std.AutoHashMap(u32, f32)) void {
        var converted = std.AutoHashMap(u32, ScrollOffset).init(self.arena.allocator());
        defer converted.deinit();
        var it = offsets.iterator();
        while (it.next()) |e| converted.put(e.key_ptr.*, .{ .y = e.value_ptr.* }) catch return;
        self.applyScrollOffsets(&converted);
        it = offsets.iterator();
        while (it.next()) |e| if (converted.get(e.key_ptr.*)) |off| {
            e.value_ptr.* = off.y;
        };
    }

    pub fn chainWheel(
        self: *const Scene,
        mouse_x: f32,
        mouse_y: f32,
        delta_x: f32,
        delta_y: f32,
        offsets: *std.AutoHashMap(u32, ScrollOffset),
    ) bool {
        var rem_x = delta_x;
        var rem_y = delta_y;
        var consumed = false;

        var current = self.scrollTarget(mouse_x, mouse_y);
        while (current) |id| {
            const item = self.find(id) orelse break;
            current = item.parent_id;
            while (current) |pid| {
                const parent = self.find(pid) orelse break;
                if (parent.node.isScrollContainer()) break;
                current = parent.parent_id;
            }
            const extent = self.scrollExtent(item.node.id);
            const entry = offsets.getOrPut(item.node.id) catch continue;
            if (!entry.found_existing) entry.value_ptr.* = .{};

            if (rem_y != 0 and item.node.isScrollContainerY()) {
                if (rem_y > 0) {
                    const room = extent.max_scroll_y - entry.value_ptr.y;
                    if (room > 0) {
                        const take = @min(rem_y, room);
                        entry.value_ptr.y += take;
                        rem_y -= take;
                        consumed = true;
                    }
                } else if (rem_y < 0) {
                    const room = entry.value_ptr.y;
                    if (room > 0) {
                        const take = @min(-rem_y, room);
                        entry.value_ptr.y -= take;
                        rem_y += take;
                        consumed = true;
                    }
                }
            }

            if (rem_x != 0 and item.node.isScrollContainerX()) {
                if (rem_x > 0) {
                    const room = extent.max_scroll_x - entry.value_ptr.x;
                    if (room > 0) {
                        const take = @min(rem_x, room);
                        entry.value_ptr.x += take;
                        rem_x -= take;
                        consumed = true;
                    }
                } else if (rem_x < 0) {
                    const room = entry.value_ptr.x;
                    if (room > 0) {
                        const take = @min(-rem_x, room);
                        entry.value_ptr.x -= take;
                        rem_x += take;
                        consumed = true;
                    }
                }
            }

            if (rem_x == 0 and rem_y == 0) break;
        }

        return consumed;
    }

    pub fn scrollTarget(self: *const Scene, x: f32, y: f32) ?u32 {
        var item = self.find(self.pointerTarget(x, y) orelse return null) orelse return null;
        while (true) {
            if (item.node.isScrollContainer()) return item.node.id;
            item = self.find(item.parent_id orelse return null) orelse return null;
        }
    }

    pub fn getFocusOrder(self: *const Scene, a: std.mem.Allocator) ![]u32 {
        var ids: std.ArrayList(u32) = .empty;
        errdefer ids.deinit(a);
        try self.collectFocus(self.root, a, &ids);
        const Ctx = struct {
            scene: *const Scene,
            fn less(c: @This(), x: u32, y: u32) bool {
                const tx = c.scene.find(x).?.node.tabIndex orelse 0;
                const ty = c.scene.find(y).?.node.tabIndex orelse 0;
                if (tx > 0 and ty <= 0) return true;
                if (tx <= 0 and ty > 0) return false;
                return tx > 0 and ty > 0 and tx < ty;
            }
        };
        std.mem.sort(u32, ids.items, Ctx{ .scene = self }, Ctx.less);
        return ids.toOwnedSlice(a);
    }
    fn collectFocus(self: *const Scene, node: *const Node, a: std.mem.Allocator, ids: *std.ArrayList(u32)) anyerror!void {
        if (self.find(node.id)) |item| if (item.node.isFocusableForTab()) try ids.append(a, node.id);
        for (node.children) |*child| try self.collectFocus(child, a, ids);
    }
    pub fn clipApplies(self: *const Scene, item: Item, ancestor: Item) bool {
        var current = item;
        var fixed = false;
        while (true) {
            const transformed = current.node.style.transform.len > 0 and !std.mem.eql(u8, current.node.style.transform, "none");
            if (current.node.id == ancestor.node.id) return !fixed or transformed;
            if (std.mem.eql(u8, current.node.style.position, "fixed")) fixed = true;
            if (fixed and transformed) fixed = false;
            current = self.find(current.parent_id orelse return true) orelse return true;
        }
    }

    pub fn establishesContext(self: *const Scene, item: Item) bool {
        const st = item.node.style;
        if (std.mem.eql(u8, st.isolation, "isolate")) return true;
        if (item.parent_id == null or st.opacity < 1 or (st.transform.len > 0 and !std.mem.eql(u8, st.transform, "none"))) return true;
        if (std.mem.eql(u8, st.position, "fixed") or std.mem.eql(u8, st.position, "sticky")) return true;
        if (st.zIndex != null) {
            if (item.node.isPositioned()) return true;
            if (item.parent_id) |pid| if (self.find(pid)) |parent| {
                const display = parent.node.style.display;
                return std.mem.eql(u8, display, "flex") or std.mem.eql(u8, display, "inline-flex") or std.mem.eql(u8, display, "grid");
            };
        }
        return false;
    }

    pub fn contextOwner(self: *const Scene, item: Item) ?u32 {
        var parent = item.parent_id;
        while (parent) |pid| {
            const p = self.find(pid) orelse return null;
            if (self.establishesContext(p)) return pid;
            parent = p.parent_id;
        }
        return null;
    }

    fn appendContext(self: *const Scene, a: std.mem.Allocator, out: *std.ArrayList(usize), root_index: usize) anyerror!void {
        try out.append(a, root_index);
        const context_id = self.items.items[root_index].node.id;
        var participants: std.ArrayList(usize) = .empty;
        defer participants.deinit(a);
        for (self.items.items, 0..) |item, i| if (self.contextOwner(item) == context_id) try participants.append(a, i);
        const Ctx = struct {
            scene: *const Scene,
            fn key(c: @This(), i: usize) i64 {
                const item = c.scene.items.items[i];
                if (c.scene.establishesContext(item)) return item.node.style.zIndex orelse 0;
                return 0;
            }
            fn less(c: @This(), i: usize, j: usize) bool {
                const zi = c.key(i);
                const zj = c.key(j);
                if (zi != zj) return zi < zj;
                return i < j;
            }
        };
        std.mem.sort(usize, participants.items, Ctx{ .scene = self }, Ctx.less);
        for (participants.items) |i| {
            if (self.establishesContext(self.items.items[i])) try self.appendContext(a, out, i) else try out.append(a, i);
        }
    }

    pub fn getPaintOrder(self: *const Scene, a: std.mem.Allocator) ![]usize {
        var out: std.ArrayList(usize) = .empty;
        errdefer out.deinit(a);
        for (self.items.items, 0..) |item, i| if (item.parent_id == null) try self.appendContext(a, &out, i);
        return out.toOwnedSlice(a);
    }

    pub fn localTransform(self: *const Scene, item: Item) transform_mod.Matrix2D {
        _ = self;
        const mat = transform_mod.parseTransformSized(item.node.style.transform, item.bounds.width, item.bounds.height) catch transform_mod.Matrix2D.identity;
        const o = transform_mod.parseTransformOrigin(item.node.style.transformOrigin, item.bounds.width, item.bounds.height);
        const x = item.bounds.x + o.x;
        const y = item.bounds.y + o.y;
        return transform_mod.Matrix2D.makeTranslate(x, y).multiply(mat).multiply(transform_mod.Matrix2D.makeTranslate(-x, -y));
    }

    pub fn worldTransform(self: *const Scene, item: Item) transform_mod.Matrix2D {
        const own = self.localTransform(item);
        if (item.parent_id) |pid| if (self.find(pid)) |p| return self.worldTransform(p).multiply(own);
        return own;
    }

    pub fn localPoint(self: *const Scene, item: Item, x: f32, y: f32) ?transform_mod.Point {
        const inv = self.worldTransform(item).inverse() orelse return null;
        return inv.transformPoint(.{ .x = x, .y = y });
    }

    pub fn pointVisible(self: *const Scene, item: Item, x: f32, y: f32) bool {
        if (!self.viewport.contains(x, y)) return false;
        var parent_id = item.parent_id;
        while (parent_id) |pid| {
            const p = self.find(pid) orelse return false;
            if (!self.clipApplies(item, p)) {
                parent_id = p.parent_id;
                continue;
            }
            const point = self.localPoint(p, x, y) orelse return false;
            const box = p.node.paddingBox(p.bounds);
            if (p.node.clipsX() and (point.x < box.x or point.x >= box.right())) return false;
            if (p.node.clipsY() and (point.y < box.y or point.y >= box.bottom())) return false;
            if (p.node.clipsX() and p.node.clipsY() and !@import("paint.zig").ellipticalContains(box, @import("paint.zig").paddingRadii(p.node, p.bounds), point.x, point.y)) return false;
            parent_id = p.parent_id;
        }
        return true;
    }

    pub fn pointerTarget(self: *const Scene, x: f32, y: f32) ?u32 {
        const a = std.heap.page_allocator;
        const order = self.getPaintOrder(a) catch return null;
        defer a.free(order);
        var i = order.len;
        while (i > 0) {
            i -= 1;
            const item = self.items.items[order[i]];
            if (!@import("interaction.zig").acceptsPointer(item.node) or std.mem.eql(u8, item.node.type, "__layout_root")) continue;
            const point = self.localPoint(item, x, y) orelse continue;
            if (@import("paint.zig").ellipticalContains(item.bounds, @import("paint.zig").resolvedRadii(item.node, item.bounds.width, item.bounds.height), point.x, point.y) and self.pointVisible(item, x, y)) return item.node.id;
        }
        return null;
    }
    pub fn hitTest(self: *const Scene, x: f32, y: f32) ?u32 {
        var item = self.find(self.pointerTarget(x, y) orelse return null) orelse return null;
        while (true) {
            if (item.node.clickable or item.node.isFocusable()) return item.node.id;
            item = self.find(item.parent_id orelse return null) orelse return null;
        }
    }
};
