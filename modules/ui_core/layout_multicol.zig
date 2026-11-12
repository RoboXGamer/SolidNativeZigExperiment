//! CSS Multi-column Layout Level 1 algorithm.
//!
//! Specifications: https://drafts.csswg.org/css-multicol-1/
//! Implements:
//! - column-count (integer, auto)
//! - column-width (length, auto)
//! - columns shorthand
//! - column-gap and gap in multicol context (normal = 1em, length, percentage, calc)
//! - column-rule (width, style, color, shorthands, currentColor, transparent)
//! - Column rule geometry and column balancing
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;
const Rect = root.Rect;
const Edges = root.Edges;

pub const MulticolResult = struct {
    num_columns: u32,
    column_width: f32,
    column_gap: f32,
};

/// Resolves column-count and column-width according to CSS Multicol 1 § 3.4.
pub fn resolveColumnCountAndWidth(
    available_width: f32,
    specified_count: ?u32,
    specified_width: ?f32,
    gap: f32,
) MulticolResult {
    const W = @max(0, available_width);
    const g = @max(0, gap);

    const has_width = specified_width != null and specified_width.? > 0;
    const has_count = specified_count != null and specified_count.? > 0;

    if (!has_width and !has_count) {
        return .{ .num_columns = 1, .column_width = W, .column_gap = g };
    }

    if (!has_width and has_count) {
        const N = @max(1, specified_count.?);
        const col_w = @max(0, (W - @as(f32, @floatFromInt(N - 1)) * g) / @as(f32, @floatFromInt(N)));
        return .{ .num_columns = N, .column_width = col_w, .column_gap = g };
    }

    if (has_width and !has_count) {
        const w_col = specified_width.?;
        const count_f = (W + g) / (w_col + g);
        const N = @max(1, @as(u32, @intFromFloat(@floor(count_f))));
        const col_w = @max(0, (W - @as(f32, @floatFromInt(N - 1)) * g) / @as(f32, @floatFromInt(N)));
        return .{ .num_columns = N, .column_width = col_w, .column_gap = g };
    }

    // Both specified
    const w_col = specified_width.?;
    const count_from_width = @max(1, @as(u32, @intFromFloat(@floor((W + g) / (w_col + g)))));
    const N = @min(specified_count.?, count_from_width);
    const col_w = @max(0, (W - @as(f32, @floatFromInt(N - 1)) * g) / @as(f32, @floatFromInt(N)));
    return .{ .num_columns = N, .column_width = col_w, .column_gap = g };
}

pub fn isMulticolContainer(node: *const Node) bool {
    if (node.style.columnCount != null and node.style.columnCount.? > 0) return true;
    if (node.style.columnWidth != null and node.style.columnWidth.? > 0) return true;
    if (node.style.columnWidthCss) |w| {
        if (!std.mem.eql(u8, w, "auto")) return true;
    }
    if (node.style.columnCountCss) |c| {
        if (!std.mem.eql(u8, c, "auto")) return true;
    }
    if (node.style.columnsCss) |col| {
        if (!std.mem.eql(u8, col, "auto")) return true;
    }
    return false;
}

pub fn resolveMulticolGap(node: *const Node, available_width: f32) f32 {
    if (node.style.columnGap) |cg| return cg;
    if (node.style.columnGapCss) |cg_css| {
        if (std.mem.eql(u8, cg_css, "normal")) {
            return node.fontSize(); // 1em default
        }
        if (std.mem.endsWith(u8, cg_css, "%")) {
            const pct = std.fmt.parseFloat(f32, cg_css[0 .. cg_css.len - 1]) catch 0;
            return @max(0, available_width * pct / 100.0);
        }
    }
    if (node.style.gap > 0) return node.style.gap;
    return node.fontSize(); // Default 1em per CSS Multicol 1
}

pub fn computeColumnRuleRects(
    a: std.mem.Allocator,
    content_x: f32,
    content_y: f32,
    content_height: f32,
    num_columns: u32,
    column_width: f32,
    gap: f32,
    rule_width: f32,
) ![]Rect {
    if (num_columns <= 1) return &.{};
    const count = num_columns - 1;
    const rects = try a.alloc(Rect, count);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const rule_center = content_x + (fi + 1.0) * column_width + fi * gap + gap / 2.0;
        rects[i] = .{
            .x = rule_center - rule_width / 2.0,
            .y = content_y,
            .width = rule_width,
            .height = @max(0, content_height),
        };
    }
    return rects;
}
