//! CSS block layout algorithm: used widths, vertical stacking, margin collapsing,
//! BFC detection, horizontal auto margin distribution, and inline formatting context (line boxes).
//!
//! Conforms to CSS 2.1 / CSS Box Model Level 3 and CSS Inline Layout Level 3.
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;
const Rect = root.Rect;
const Edges = root.Edges;
const Scene = root.Scene;

/// A set of margins that are available for collapsing in block layout.
/// Preserves the largest positive margin and smallest negative margin.
pub const CollapsibleMarginSet = struct {
    positive: f32 = 0,
    negative: f32 = 0,

    pub const zero: CollapsibleMarginSet = .{ .positive = 0, .negative = 0 };

    pub fn fromMargin(m: f32) CollapsibleMarginSet {
        if (m >= 0) return .{ .positive = m, .negative = 0 };
        return .{ .positive = 0, .negative = m };
    }

    pub fn collapseWithMargin(self: CollapsibleMarginSet, m: f32) CollapsibleMarginSet {
        var res = self;
        if (m >= 0) {
            res.positive = @max(res.positive, m);
        } else {
            res.negative = @min(res.negative, m);
        }
        return res;
    }

    pub fn collapseWithSet(self: CollapsibleMarginSet, other: CollapsibleMarginSet) CollapsibleMarginSet {
        return .{
            .positive = @max(self.positive, other.positive),
            .negative = @min(self.negative, other.negative),
        };
    }

    pub fn resolve(self: CollapsibleMarginSet) f32 {
        return self.positive + self.negative;
    }
};

/// CSS margin collapsing for two adjoining margins (kept for backwards compatibility).
pub fn collapsePair(a: f32, b: f32) f32 {
    return CollapsibleMarginSet.fromMargin(a).collapseWithMargin(b).resolve();
}

/// Detects whether a node establishes an independent Block Formatting Context (BFC).
/// Per CSS Display 3 and CSS Overflow 3:
/// - display: flow-root establishes a BFC.
/// - overflow: hidden, scroll, auto establish a BFC.
/// - overflow: visible and overflow: clip do NOT establish a BFC.
pub fn establishesBfc(n: *const Node) bool {
    if (!std.mem.eql(u8, n.style.float, "none")) return true;
    if (std.mem.eql(u8, n.style.display, "flow-root")) return true;
    if (root.layout_multicol.isMulticolContainer(n)) return true;
    const ox = n.effectiveOverflowX();
    const oy = n.effectiveOverflowY();
    const is_bfc_val = struct {
        fn check(val: []const u8) bool {
            return std.mem.eql(u8, val, "hidden") or
                std.mem.eql(u8, val, "scroll") or
                std.mem.eql(u8, val, "auto");
        }
    }.check;
    return is_bfc_val(ox) or is_bfc_val(oy);
}

/// Checks if a child participates in an Inline Formatting Context (IFC) rather than block flow.
pub fn isInlineLevel(child: *const Node) bool {
    return std.mem.eql(u8, child.type, "text") or
        std.mem.eql(u8, child.style.display, "inline") or
        std.mem.eql(u8, child.style.display, "inline-block") or
        std.mem.eql(u8, child.style.display, "inline-flex");
}

fn alignmentShift(n: *const Node, free: f32, last: bool) f32 {
    if (free <= 0) return 0;
    const alignment = if (last and !std.mem.eql(u8, n.style.textAlignLast, "auto")) n.style.textAlignLast else n.style.textAlign;
    if (std.mem.eql(u8, alignment, "center")) return free * 0.5;
    const rtl = std.mem.eql(u8, n.style.direction, "rtl");
    if (std.mem.eql(u8, alignment, "right") or (std.mem.eql(u8, alignment, "start") and rtl) or (std.mem.eql(u8, alignment, "end") and !rtl)) return free;
    return 0;
}
pub const BlockChildLayout = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    used_margin: Edges,
    is_empty: bool,
};

pub const BlockLayoutOutput = struct {
    consumed_height: f32,
    collapsible_top: CollapsibleMarginSet,
    collapsible_bottom: CollapsibleMarginSet,
    is_empty: bool,
};

fn floatSide(value: []const u8, parent: *const Node) ?bool {
    const rtl = std.mem.eql(u8, parent.style.direction, "rtl");
    if (std.mem.eql(u8, value, "left")) return false;
    if (std.mem.eql(u8, value, "right")) return true;
    if (std.mem.eql(u8, value, "inline-start")) return rtl;
    if (std.mem.eql(u8, value, "inline-end")) return !rtl;
    return null;
}

const FloatSpace = struct { left: f32 = 0, right: f32, next: ?f32 = null };
fn floatSpace(n: *const Node, positions: []const BlockChildLayout, upto: usize, width: f32, y: f32, height: f32) FloatSpace {
    var space = FloatSpace{ .right = width };
    for (n.children[0..upto], positions[0..upto]) |*child, position| {
        const right = floatSide(child.style.float, n) orelse continue;
        if (child.isOutOfFlow()) continue;
        const margin = position.used_margin;
        const top = position.y - margin.top;
        const bottom = position.y + position.height + margin.bottom;
        if (bottom <= y or top >= y + @max(0.001, height)) continue;
        if (right) space.right = @min(space.right, position.x - margin.left) else space.left = @max(space.left, position.x + position.width + margin.right);
        if (space.next == null or bottom < space.next.?) space.next = bottom;
    }
    return space;
}

/// Computes block layout sizing, margin collapsing, line boxes, and positioning.
/// Used both for measuring natural height and for the final layout pass.
pub fn computeBlockLayout(
    scene: *const Scene,
    n: *const Node,
    inner_width: f32,
    children_output: ?[]BlockChildLayout,
) BlockLayoutOutput {
    var has_float = false;
    for (n.children) |*child| if (!child.isOutOfFlow() and floatSide(child.style.float, n) != null) {
        has_float = true;
    };
    // Measurement and layout use the same exclusions, including when a caller
    // requests only height. Scratch storage is released on every measurement.
    const scratch = if (children_output == null and has_float) std.heap.page_allocator.alloc(BlockChildLayout, n.children.len) catch @panic("float layout scratch allocation failed") else null;
    defer if (scratch) |positions| std.heap.page_allocator.free(positions);
    const children_out = children_output orelse scratch;
    const pad = n.padding();
    const bd = n.border();
    const bfc = establishesBfc(n);
    const parent_can_collapse_top = pad.top == 0 and bd.top == 0 and !bfc;
    const parent_can_collapse_bottom = n.style.height == null and pad.bottom == 0 and bd.bottom == 0 and !bfc;

    var cursor_y: f32 = 0;
    var margin_strut = CollapsibleMarginSet.zero;
    var collapsible_top = CollapsibleMarginSet.zero;
    var has_in_flow_content = false;

    var in_inline_run = false;
    var line_start: usize = 0;
    var line_x: f32 = 0;
    var line_h: f32 = 0;

    for (n.children, 0..) |*child, i| {
        if (child.isOutOfFlow()) {
            if (children_out) |out| {
                const inline_position = child.style.positionInline or std.mem.eql(u8, child.type, "text");
                out[i] = .{
                    .x = if (inline_position and in_inline_run) line_x else 0,
                    .y = cursor_y + (if (in_inline_run and !inline_position) line_h else if (!in_inline_run) margin_strut.resolve() else 0),
                    .width = 0,
                    .height = 0,
                    .used_margin = .{},
                    .is_empty = true,
                };
            }
            continue;
        }
        const child_mg = child.margin();
        const child_bd = child.border();
        const child_pad = child.padding();
        const child_inset_x = child_pad.horizontal() + child_bd.horizontal();

        if (children_out) |positions| {
            if (!std.mem.eql(u8, child.style.clear, "none")) {
                const side = floatSide(child.style.clear, n);
                var clearance = cursor_y;
                for (n.children[0..i], positions[0..i]) |*previous, position| {
                    const previous_side = floatSide(previous.style.float, n) orelse continue;
                    if (previous.isOutOfFlow()) continue;
                    if (std.mem.eql(u8, child.style.clear, "both") or side == previous_side) clearance = @max(clearance, position.y + position.height + position.used_margin.bottom);
                }
                if (clearance > cursor_y) {
                    cursor_y = clearance;
                    line_x = 0;
                    line_h = 0;
                    in_inline_run = false;
                    margin_strut = CollapsibleMarginSet.zero;
                    has_in_flow_content = true;
                }
            }
            if (floatSide(child.style.float, n)) |right| {
                var y = cursor_y;
                const width = child.constrain(if (child.style.width) |value| child.borderSize(value, child_inset_x) else scene.intrinsicWidthFor(child, .{ .definite = @max(0, inner_width - child_mg.horizontal()) }), true);
                const height = scene.naturalHeightForWidth(child, width);
                var space = floatSpace(n, positions, i, inner_width, y, height + child_mg.vertical());
                while (width + child_mg.horizontal() > space.right - space.left and space.next != null) {
                    y = space.next.?;
                    space = floatSpace(n, positions, i, inner_width, y, height + child_mg.vertical());
                }
                positions[i] = .{ .x = if (right) space.right - width - child_mg.right else space.left + child_mg.left, .y = y + child_mg.top, .width = width, .height = height, .used_margin = child_mg, .is_empty = false };
                continue;
            }
        }

        if (isInlineLevel(child)) {
            // Inline box formatting context
            var child_w = child.constrain(if (child.style.width) |width|
                child.borderSize(width, child_inset_x)
            else
                scene.intrinsicWidthFor(child, if (inner_width > 0) .{ .definite = inner_width } else .max_content), true);

            if (child.style.width == null and child.style.height != null) {
                if (child.aspectRatio()) |ratio| {
                    const inset_y = child_pad.vertical() + child_bd.vertical();
                    const border_height = child.constrain(child.borderSize(child.style.height.?, inset_y), false);
                    const basis = if (std.mem.eql(u8, child.style.boxSizing, "content-box")) @max(0, border_height - inset_y) else border_height;
                    child_w = child.constrain(child.borderSize(basis * ratio, child_inset_x), true);
                }
            }

            const child_h = scene.naturalHeightForWidth(child, child_w);
            const item_outer_w = child_w + child_mg.horizontal();

            var float_left: f32 = 0;
            var float_right = inner_width;
            if (children_out) |positions| {
                var space = floatSpace(n, positions, i, inner_width, cursor_y, child_h + child_mg.vertical());
                while (item_outer_w > space.right - space.left and space.next != null) {
                    cursor_y = @max(cursor_y + line_h, space.next.?);
                    line_x = 0;
                    line_h = 0;
                    in_inline_run = false;
                    space = floatSpace(n, positions, i, inner_width, cursor_y, child_h + child_mg.vertical());
                }
                float_left = space.left;
                float_right = space.right;
                line_x = @max(line_x, float_left);
            }

            if (in_inline_run and inner_width > 0 and line_x + item_outer_w > float_right and i > line_start) {
                // Wrap to a new line box
                const free_line_x = inner_width - line_x;
                if (children_out) |out| {
                    const shift = alignmentShift(n, free_line_x, false);
                    if (shift > 0) {
                        for (out[line_start..i]) |*item| item.x += shift;
                    }
                }
                cursor_y += line_h;
                line_x = if (children_out) |positions| floatSpace(n, positions, i, inner_width, cursor_y, child_h + child_mg.vertical()).left else 0;
                line_h = 0;
                line_start = i;
            }

            if (!in_inline_run) {
                const is_first_content = !has_in_flow_content;
                if (!has_in_flow_content) {
                    if (!parent_can_collapse_top) {
                        cursor_y += margin_strut.resolve();
                    }
                    has_in_flow_content = true;
                } else {
                    cursor_y += margin_strut.resolve();
                }
                margin_strut = CollapsibleMarginSet.zero;
                in_inline_run = true;
                line_start = i;
                line_x = float_left + if (is_first_content) (n.style.textIndent orelse 0) else @as(f32, 0);
                line_h = 0;
            }

            const child_x = line_x + child_mg.left;
            const child_y = cursor_y + child_mg.top;
            line_x += item_outer_w;
            line_h = @max(line_h, child_h + child_mg.vertical());

            if (children_out) |out| {
                out[i] = .{
                    .x = child_x,
                    .y = child_y,
                    .width = child_w,
                    .height = child_h,
                    .used_margin = child_mg,
                    .is_empty = false,
                };
            }
            continue;
        }

        // Child is a block-level box
        if (in_inline_run) {
            // Flush preceding inline line box
            const free_line_x = inner_width - line_x;
            if (children_out) |out| {
                const shift = alignmentShift(n, free_line_x, true);
                if (shift > 0) {
                    for (out[line_start..i]) |*item| item.x += shift;
                }
            }
            cursor_y += line_h;
            line_x = 0;
            line_h = 0;
            in_inline_run = false;
        }

        var child_w = child.constrain(if (child.style.width) |width|
            child.borderSize(width, child_inset_x)
        else
            @max(0, inner_width - child_mg.horizontal()), true);

        if (child.style.width == null and child.style.height != null) {
            if (child.aspectRatio()) |ratio| {
                const inset_y = child_pad.vertical() + child_bd.vertical();
                const border_height = child.constrain(child.borderSize(child.style.height.?, inset_y), false);
                const basis = if (std.mem.eql(u8, child.style.boxSizing, "content-box")) @max(0, border_height - inset_y) else border_height;
                child_w = child.constrain(child.borderSize(basis * ratio, child_inset_x), true);
            }
        }

        var available_width = inner_width;
        var float_offset: f32 = 0;
        if (establishesBfc(child)) if (children_out) |positions| {
            var y = cursor_y + margin_strut.resolve() + child_mg.top;
            var space = floatSpace(n, positions, i, inner_width, y, scene.naturalHeightForWidth(child, child_w) + child_mg.vertical());
            if (child.style.width == null) child_w = child.constrain(@max(0, space.right - space.left - child_mg.horizontal()), true);
            while (child_w + child_mg.horizontal() > space.right - space.left and space.next != null) {
                y = space.next.?;
                space = floatSpace(n, positions, i, inner_width, y, scene.naturalHeightForWidth(child, child_w) + child_mg.vertical());
            }
            const next_cursor = y - margin_strut.resolve() - child_mg.top;
            if (next_cursor > cursor_y) {
                cursor_y = next_cursor;
                has_in_flow_content = true;
            }
            available_width = space.right - space.left;
            float_offset = space.left;
        };
        const free_x = available_width - child_w - child_mg.horizontal();
        var auto_left: f32 = 0;
        var auto_right: f32 = 0;
        if (child.style.marginLeftAuto and child.style.marginRightAuto) {
            if (free_x > 0) {
                auto_left = free_x * 0.5;
                auto_right = free_x * 0.5;
            } else {
                auto_left = 0;
                auto_right = 0;
            }
        } else if (child.style.marginLeftAuto) {
            if (free_x > 0) auto_left = free_x;
        } else if (child.style.marginRightAuto) {
            if (free_x > 0) auto_right = free_x;
        }

        const child_h = scene.naturalHeightForWidth(child, child_w);

        const is_empty = child_h == 0 and child.style.height == null and child.style.minHeight == null and child.children.len == 0 and
            child_pad.vertical() == 0 and child_bd.vertical() == 0;

        margin_strut = margin_strut.collapseWithMargin(child_mg.top);

        var child_y: f32 = 0;
        if (is_empty) {
            margin_strut = margin_strut.collapseWithMargin(child_mg.bottom);
            if (!has_in_flow_content) {
                if (parent_can_collapse_top) {
                    collapsible_top = margin_strut;
                    child_y = 0;
                } else {
                    child_y = margin_strut.resolve();
                }
            } else {
                child_y = cursor_y;
            }
        } else {
            if (!has_in_flow_content) {
                has_in_flow_content = true;
                if (parent_can_collapse_top) {
                    collapsible_top = margin_strut;
                    child_y = 0;
                    cursor_y = child_h;
                } else {
                    cursor_y = margin_strut.resolve();
                    child_y = cursor_y;
                    cursor_y += child_h;
                }
            } else {
                cursor_y += margin_strut.resolve();
                child_y = cursor_y;
                cursor_y += child_h;
            }
            margin_strut = CollapsibleMarginSet.fromMargin(child_mg.bottom);
        }

        if (children_out) |out| {
            var used_margin = child_mg;
            used_margin.left += auto_left;
            used_margin.right += auto_right;
            out[i] = .{
                .x = float_offset + child_mg.left + auto_left + (if (std.mem.eql(u8, n.style.direction, "rtl") and !child.style.marginLeftAuto and !child.style.marginRightAuto) free_x else @as(f32, 0)),
                .y = child_y,
                .width = child_w,
                .height = child_h,
                .used_margin = used_margin,
                .is_empty = is_empty,
            };
        }
    }

    if (in_inline_run) {
        const free_line_x = inner_width - line_x;
        if (children_out) |out| {
            const shift = alignmentShift(n, free_line_x, true);
            if (shift > 0) {
                for (out[line_start..n.children.len]) |*item| item.x += shift;
            }
        }
        cursor_y += line_h;
    }

    var collapsible_bottom = CollapsibleMarginSet.zero;
    var consumed_height: f32 = 0;

    if (!has_in_flow_content) {
        if (parent_can_collapse_top and parent_can_collapse_bottom) {
            collapsible_top = margin_strut;
            collapsible_bottom = margin_strut;
            consumed_height = 0;
        } else if (parent_can_collapse_bottom) {
            collapsible_bottom = margin_strut;
            consumed_height = cursor_y;
        } else {
            consumed_height = cursor_y + margin_strut.resolve();
        }
    } else {
        if (parent_can_collapse_bottom) {
            collapsible_bottom = margin_strut;
            consumed_height = cursor_y;
        } else {
            consumed_height = cursor_y + margin_strut.resolve();
        }
    }

    if (bfc) if (children_out) |positions| {
        for (n.children, positions) |*child, position| {
            if (!child.isOutOfFlow() and floatSide(child.style.float, n) != null) consumed_height = @max(consumed_height, position.y + position.height + position.used_margin.bottom);
        }
    };

    return .{
        .consumed_height = consumed_height,
        .collapsible_top = collapsible_top,
        .collapsible_bottom = collapsible_bottom,
        .is_empty = !has_in_flow_content and n.children.len > 0,
    };
}

pub fn layout(self: *Scene, n: *const Node, bounds: Rect, inner_width: f32) anyerror!void {
    const pad = n.padding();
    const bd = n.border();
    const gutter = n.scrollbarGutterReserved();
    const content_top = bounds.y + pad.top + bd.top + gutter.top;
    const content_left = bounds.x + pad.left + bd.left + gutter.left;

    const count = n.children.len;
    if (count == 0) return;

    if (root.layout_multicol.isMulticolContainer(n)) {
        const gap = root.layout_multicol.resolveMulticolGap(n, inner_width);
        const multicol = root.layout_multicol.resolveColumnCountAndWidth(inner_width, n.style.columnCount, n.style.columnWidth, gap);
        if (multicol.num_columns > 1) {
            const child_layouts = try self.arena.allocator().alloc(BlockChildLayout, count);
            _ = computeBlockLayout(self, n, multicol.column_width, child_layouts);

            var total_h: f32 = 0;
            for (n.children, 0..) |*child, i| {
                if (!child.isOutOfFlow()) {
                    total_h += child_layouts[i].height + child_layouts[i].used_margin.vertical();
                }
            }
            const target_col_h = @max(1, total_h / @as(f32, @floatFromInt(multicol.num_columns)));

            var col_idx: u32 = 0;
            var col_y: f32 = 0;

            for (n.children, 0..) |*child, i| {
                if (child.isOutOfFlow()) continue;
                const cl = child_layouts[i];
                const item_h = cl.height + cl.used_margin.vertical();
                if (col_y > 0 and col_y + item_h > target_col_h and col_idx + 1 < multicol.num_columns) {
                    col_idx += 1;
                    col_y = 0;
                }
                const col_x = @as(f32, @floatFromInt(col_idx)) * (multicol.column_width + multicol.column_gap);
                const child_rect = Rect{
                    .x = content_left + col_x + cl.x,
                    .y = content_top + col_y + cl.used_margin.top,
                    .width = cl.width,
                    .height = cl.height,
                };
                try self.layout(child, child_rect, n.id);
                self.setUsedMargin(child.id, cl.used_margin);
                col_y += item_h;
            }
            return;
        }
    }

    const vertical = !std.mem.eql(u8, n.style.writingMode, "horizontal-tb");
    const is_v_rl = std.mem.endsWith(u8, n.style.writingMode, "-rl");
    const content_width = bounds.width - pad.horizontal() - bd.horizontal();
    const content_height = bounds.height - pad.vertical() - bd.vertical();
    const child_layouts = try self.arena.allocator().alloc(BlockChildLayout, count);
    if (vertical) {
        var projected = n.*;
        projected.children = try self.arena.allocator().dupe(Node, n.children);
        const sideways_lr = std.mem.eql(u8, n.style.writingMode, "sideways-lr");
        if (sideways_lr) projected.style.direction = if (std.mem.eql(u8, n.style.direction, "rtl")) "ltr" else "rtl";
        projectDimensions(&projected, is_v_rl);
        for (projected.children) |*child| projectDimensions(child, is_v_rl);
        _ = computeBlockLayout(self, &projected, content_height, child_layouts);
    } else {
        _ = computeBlockLayout(self, n, inner_width, child_layouts);
    }

    for (n.children, 0..) |*child, i| {
        if (child.isOutOfFlow()) continue;
        const cl = child_layouts[i];
        const child_rect = if (vertical) Rect{
            .x = if (is_v_rl) content_left + @max(0, content_width - cl.y - cl.height) else content_left + cl.y,
            .y = content_top + cl.x,
            .width = cl.height,
            .height = cl.width,
        } else Rect{
            .x = content_left + cl.x,
            .y = content_top + cl.y,
            .width = cl.width,
            .height = cl.height,
        };
        try self.layout(child, child_rect, n.id);
        self.setUsedMargin(child.id, if (vertical) .{
            .top = cl.used_margin.left,
            .right = if (is_v_rl) cl.used_margin.top else cl.used_margin.bottom,
            .bottom = cl.used_margin.right,
            .left = if (is_v_rl) cl.used_margin.bottom else cl.used_margin.top,
        } else cl.used_margin);
    }
}

// Block/float algorithms operate in inline/block coordinates. Preserve the
// original physical styles for scene layout and painting after projection.
fn projectDimensions(n: *Node, block_reverse: bool) void {
    inline for (.{ .{ "width", "height" }, .{ "minWidth", "minHeight" }, .{ "maxWidth", "maxHeight" } }) |pair| {
        std.mem.swap(?f32, &@field(n.style, pair[0]), &@field(n.style, pair[1]));
        std.mem.swap(?[]const u8, &@field(n.style, pair[0] ++ "Css"), &@field(n.style, pair[1] ++ "Css"));
    }
    inline for (.{ "Style", "Color" }) |suffix| {
        const top = @field(n.style, "borderTop" ++ suffix);
        const right = @field(n.style, "borderRight" ++ suffix);
        const bottom = @field(n.style, "borderBottom" ++ suffix);
        const left = @field(n.style, "borderLeft" ++ suffix);
        @field(n.style, "borderTop" ++ suffix) = if (block_reverse) right else left;
        @field(n.style, "borderBottom" ++ suffix) = if (block_reverse) left else right;
        @field(n.style, "borderLeft" ++ suffix) = top;
        @field(n.style, "borderRight" ++ suffix) = bottom;
    }
    inline for (.{ "padding", "margin", "border" }) |prefix| {
        const suffix = comptime if (std.mem.eql(u8, prefix, "border")) "Width" else "";
        const top = @field(n.style, prefix ++ "Top" ++ suffix);
        const right = @field(n.style, prefix ++ "Right" ++ suffix);
        const bottom = @field(n.style, prefix ++ "Bottom" ++ suffix);
        const left = @field(n.style, prefix ++ "Left" ++ suffix);
        @field(n.style, prefix ++ "Top" ++ suffix) = if (block_reverse) right else left;
        @field(n.style, prefix ++ "Bottom" ++ suffix) = if (block_reverse) left else right;
        @field(n.style, prefix ++ "Left" ++ suffix) = top;
        @field(n.style, prefix ++ "Right" ++ suffix) = bottom;
    }
    const mt = n.style.marginTopAuto;
    const mr = n.style.marginRightAuto;
    const mb = n.style.marginBottomAuto;
    const ml = n.style.marginLeftAuto;
    n.style.marginTopAuto = if (block_reverse) mr else ml;
    n.style.marginBottomAuto = if (block_reverse) ml else mr;
    n.style.marginLeftAuto = mt;
    n.style.marginRightAuto = mb;
}
