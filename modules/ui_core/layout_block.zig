//! Partial CSS block flow: vertical stacking with margin collapsing.
//!
//! Not a full block formatting context: no floats, no inline formatting, no
//! percentage/auto block sizes. See docs/html-css-reference.md.
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;
const Rect = root.Rect;
const Scene = root.Scene;

/// CSS margin collapsing for two adjoining margins: positives take the larger
/// magnitude, negatives the smaller (most negative), opposite signs add.
pub fn collapsePair(a: f32, b: f32) f32 {
    if (a >= 0 and b >= 0) return @max(a, b);
    if (a < 0 and b < 0) return @min(a, b);
    return a + b;
}

pub fn layout(self: *Scene, n: *const Node, bounds: Rect, inner_width: f32) anyerror!void {
    const pad = n.padding();
    const bd = n.border();

    var cursor_y: f32 = 0;
    var prev_mb: f32 = 0;
    var first_child = true;
    const parent_bfc = std.mem.eql(u8, n.style.display, "flow-root") or !std.mem.eql(u8, n.style.overflow, "visible");
    const parent_can_collapse_top = pad.top == 0 and bd.top == 0 and !parent_bfc;

    for (n.children) |*child| {
        const child_mg = child.margin();
        const cmt = child_mg.top;
        const cmb = child_mg.bottom;
        const child_bd = child.border();
        const child_pad = child.padding();
        const child_inset_x = child_pad.horizontal() + child_bd.horizontal();
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
        const free = @max(0, inner_width - child_w - child_mg.horizontal());
        const auto_count: u8 = @intFromBool(child.style.marginLeftAuto) + @as(u8, @intFromBool(child.style.marginRightAuto));
        const auto_left = if (child.style.marginLeftAuto and auto_count > 0) free / @as(f32, @floatFromInt(auto_count)) else 0;
        const auto_right = if (child.style.marginRightAuto and auto_count > 0) free / @as(f32, @floatFromInt(auto_count)) else 0;
        const child_h = self.naturalHeightForWidth(child, child_w);

        // A box with no content, no fixed height and no padding/border collapses
        // through: its top and bottom margins join the adjoining margins.
        const is_empty = child_h == 0 and child.style.height == null and child.children.len == 0 and
            child_pad.vertical() == 0 and child_bd.vertical() == 0;

        const content_top = bounds.y + pad.top + bd.top;
        const x = bounds.x + pad.left + bd.left + child_mg.left + auto_left;

        if (is_empty) {
            // The empty box renders at zero height; its margins merge into the
            // gap left for the next sibling instead of advancing the cursor.
            const own_top = if (first_child) cmt else collapsePair(prev_mb, cmt);
            const y0 = if (first_child)
                content_top + (if (parent_can_collapse_top) 0 else cmt)
            else
                content_top + cursor_y + own_top;
            try self.layout(child, .{ .x = x, .y = y0, .width = child_w, .height = 0 }, n.id);
            var used_margin = child_mg;
            used_margin.left += auto_left;
            used_margin.right += auto_right;
            self.setUsedMargin(child.id, used_margin);
            prev_mb = if (first_child) collapsePair(cmt, cmb) else collapsePair(own_top, cmb);
            first_child = false;
            continue;
        }

        var margin_before: f32 = 0;
        if (first_child) {
            if (parent_can_collapse_top) {
                margin_before = 0;
            } else {
                margin_before = cmt;
            }
        } else {
            margin_before = collapsePair(prev_mb, cmt);
        }

        const y = if (first_child)
            content_top + (if (parent_can_collapse_top) 0 else cmt)
        else
            content_top + cursor_y + margin_before;
        try self.layout(child, .{ .x = x, .y = y, .width = child_w, .height = child_h }, n.id);
        var used_margin = child_mg;
        used_margin.left += auto_left;
        used_margin.right += auto_right;
        self.setUsedMargin(child.id, used_margin);
        const used_height = self.find(child.id).?.bounds.height;

        if (first_child) {
            cursor_y = (if (parent_can_collapse_top) 0 else cmt) + used_height;
        } else {
            cursor_y = cursor_y + margin_before + used_height;
        }
        prev_mb = cmb;
        first_child = false;
    }
}
