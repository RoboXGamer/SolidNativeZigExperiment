//! CSS Table layout algorithm conforming to CSS 2.1 / CSS 2024 Table module.
//! Supports:
//! - border-collapse: separate and collapse
//! - border-spacing: horizontal and vertical spacing
//! - caption-side: top and bottom
//! - empty-cells: show and hide
//! - table-layout: auto and fixed
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;
const Rect = root.Rect;
const Edges = root.Edges;
const Scene = root.Scene;

pub const TableCell = struct {
    node: *const Node,
    col_index: usize,
    row_index: usize,
    min_width: f32 = 0,
    max_width: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    is_empty: bool = false,
};

pub const TableRow = struct {
    node: *const Node,
    cells: []TableCell,
    height: f32 = 0,
    y: f32 = 0,
};

pub fn isTable(n: *const Node) bool {
    return std.mem.eql(u8, n.style.display, "table") or std.mem.eql(u8, n.type, "table");
}

pub fn isCaption(n: *const Node) bool {
    return std.mem.eql(u8, n.style.display, "table-caption") or std.mem.eql(u8, n.type, "caption");
}

pub fn isRowGroup(n: *const Node) bool {
    return std.mem.eql(u8, n.style.display, "table-row-group") or
        std.mem.eql(u8, n.style.display, "table-header-group") or
        std.mem.eql(u8, n.style.display, "table-footer-group") or
        std.mem.eql(u8, n.type, "thead") or
        std.mem.eql(u8, n.type, "tbody") or
        std.mem.eql(u8, n.type, "tfoot");
}

pub fn isRow(n: *const Node) bool {
    return std.mem.eql(u8, n.style.display, "table-row") or std.mem.eql(u8, n.type, "tr");
}

pub fn isCell(n: *const Node) bool {
    return std.mem.eql(u8, n.style.display, "table-cell") or std.mem.eql(u8, n.type, "td") or std.mem.eql(u8, n.type, "th");
}

pub fn isCellEmpty(cell_node: *const Node) bool {
    if (cell_node.text.len > 0) {
        for (cell_node.text) |c| {
            if (c != ' ' and c != '\t' and c != '\r' and c != '\n') return false;
        }
    }
    for (cell_node.children) |*child| {
        if (!isCellEmpty(child)) return false;
    }
    return true;
}

pub fn collectRows(allocator: std.mem.Allocator, table_node: *const Node) ![]*const Node {
    var rows = std.ArrayList(*const Node).init(allocator);
    errdefer rows.deinit();

    for (table_node.children) |*child| {
        if (child.isOutOfFlow() or isCaption(child)) continue;
        if (isRowGroup(child)) {
            for (child.children) |*sub_child| {
                if (sub_child.isOutOfFlow()) continue;
                if (isRow(sub_child)) {
                    try rows.append(sub_child);
                }
            }
        } else if (isRow(child)) {
            try rows.append(child);
        }
    }
    return rows.toOwnedSlice();
}

pub fn collectCells(allocator: std.mem.Allocator, row_node: *const Node) ![]*const Node {
    var cells = std.ArrayList(*const Node).init(allocator);
    errdefer cells.deinit();

    for (row_node.children) |*child| {
        if (child.isOutOfFlow()) continue;
        if (isCell(child)) {
            try cells.append(child);
        }
    }
    return cells.toOwnedSlice();
}

pub fn measureHeight(scene: *const Scene, n: *const Node, inner_width: f32) f32 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const rows = collectRows(a, n) catch return 0;
    if (rows.len == 0) return 0;

    const collapse = std.mem.eql(u8, n.style.borderCollapse, "collapse");
    const spacing_y = if (collapse) 0 else n.style.borderSpacingY;
    const spacing_x = if (collapse) 0 else n.style.borderSpacingX;

    // Find column count
    var max_cols: usize = 0;
    for (rows) |r| {
        const cells = collectCells(a, r) catch continue;
        if (cells.len > max_cols) max_cols = cells.len;
    }
    if (max_cols == 0) return 0;

    const total_spacing_x = if (collapse) 0 else spacing_x * @as(f32, @floatFromInt(max_cols + 1));
    const available_cols_width = @max(0, inner_width - total_spacing_x);
    const col_width = available_cols_width / @as(f32, @floatFromInt(max_cols));

    var total_height: f32 = if (collapse) 0 else spacing_y;
    for (rows) |r| {
        const cells = collectCells(a, r) catch continue;
        var row_h: f32 = 0;
        for (cells) |c| {
            const h = scene.naturalHeightForWidth(c, col_width);
            if (h > row_h) row_h = h;
        }
        total_height += row_h + spacing_y;
    }

    // Add caption heights
    for (n.children) |*child| {
        if (isCaption(child) and !child.isOutOfFlow()) {
            total_height += scene.naturalHeightForWidth(child, inner_width);
        }
    }

    return total_height;
}

pub fn layout(scene: *Scene, n: *const Node, bounds: Rect, inner_width: f32, inner_height: f32) anyerror!void {
    _ = inner_height;
    const a = scene.arena.allocator();
    const pad = n.padding();
    const bd = n.border();
    const content_x = bounds.x + pad.left + bd.left;
    var current_y = bounds.y + pad.top + bd.top;

    const collapse = std.mem.eql(u8, n.style.borderCollapse, "collapse");
    const spacing_x = if (collapse) 0 else n.style.borderSpacingX;
    const spacing_y = if (collapse) 0 else n.style.borderSpacingY;
    const hide_empty = !collapse and std.mem.eql(u8, n.style.emptyCells, "hide");
    const is_fixed = std.mem.eql(u8, n.style.tableLayout, "fixed");
    const caption_top = !std.mem.eql(u8, n.style.captionSide, "bottom");

    // Layout captions with caption-side: top
    for (n.children) |*child| {
        if (isCaption(child) and caption_top and !child.isOutOfFlow()) {
            const cap_h = scene.naturalHeightForWidth(child, inner_width);
            try scene.layout(child, .{ .x = content_x, .y = current_y, .width = inner_width, .height = cap_h }, n.id);
            current_y += cap_h;
        }
    }

    // Collect all rows and structure
    const row_nodes = try collectRows(a, n);
    if (row_nodes.len == 0) {
        // Layout remaining captions with caption-side: bottom
        for (n.children) |*child| {
            if (isCaption(child) and !caption_top and !child.isOutOfFlow()) {
                const cap_h = scene.naturalHeightForWidth(child, inner_width);
                try scene.layout(child, .{ .x = content_x, .y = current_y, .width = inner_width, .height = cap_h }, n.id);
                current_y += cap_h;
            }
        }
        return;
    }

    var col_count: usize = 0;
    for (row_nodes) |r| {
        const cells = try collectCells(a, r);
        if (cells.len > col_count) col_count = cells.len;
    }
    if (col_count == 0) return;

    const col_widths = try a.alloc(f32, col_count);
    @memset(col_widths, 0);

    const total_spacing_x = if (collapse) 0 else spacing_x * @as(f32, @floatFromInt(col_count + 1));
    const available_grid_w = @max(0, inner_width - total_spacing_x);

    if (is_fixed) {
        // Fixed table layout: first row dictates column widths
        const first_row_cells = try collectCells(a, row_nodes[0]);
        var explicit_total: f32 = 0;
        var unassigned_count: usize = 0;
        for (0..col_count) |col| {
            if (col < first_row_cells.len and first_row_cells[col].style.width != null) {
                const w = first_row_cells[col].style.width.?;
                col_widths[col] = w;
                explicit_total += w;
            } else {
                unassigned_count += 1;
            }
        }
        const rem_w = @max(0, available_grid_w - explicit_total);
        const per_unassigned = if (unassigned_count > 0) rem_w / @as(f32, @floatFromInt(unassigned_count)) else 0;
        for (0..col_count) |col| {
            if (col_widths[col] == 0) col_widths[col] = per_unassigned;
        }
    } else {
        // Auto table layout: inspect cells across all rows
        const min_widths = try a.alloc(f32, col_count);
        const max_widths = try a.alloc(f32, col_count);
        @memset(min_widths, 0);
        @memset(max_widths, 0);

        for (row_nodes) |r| {
            const cells = try collectCells(a, r);
            for (cells, 0..) |c, col| {
                if (col >= col_count) break;
                const explicit_w = c.style.width;
                const min_w = if (explicit_w) |w| w else scene.naturalWidth(c);
                const max_w = if (explicit_w) |w| w else scene.naturalWidth(c);
                if (min_w > min_widths[col]) min_widths[col] = min_w;
                if (max_w > max_widths[col]) max_widths[col] = max_w;
            }
        }

        var total_max: f32 = 0;
        for (max_widths) |w| total_max += w;

        if (total_max > 0 and total_max <= available_grid_w) {
            // Allocate proportionally
            for (0..col_count) |col| {
                col_widths[col] = max_widths[col] + (available_grid_w - total_max) / @as(f32, @floatFromInt(col_count));
            }
        } else {
            // Distribute available width proportionally to min_widths
            var total_min: f32 = 0;
            for (min_widths) |w| total_min += w;
            if (total_min > 0) {
                for (0..col_count) |col| {
                    col_widths[col] = @max(min_widths[col], available_grid_w * (min_widths[col] / total_min));
                }
            } else {
                const equal_w = available_grid_w / @as(f32, @floatFromInt(col_count));
                for (0..col_count) |col| col_widths[col] = equal_w;
            }
        }
    }

    // Grid starts after top spacing
    current_y += spacing_y;

    // Lay out rows and cells
    for (row_nodes) |r| {
        const cells = try collectCells(a, r);
        var row_h: f32 = r.style.height orelse 0;

        // First pass: measure row height from cells
        for (cells, 0..) |c, col| {
            if (col >= col_count) break;
            if (hide_empty and isCellEmpty(c)) continue;
            const h = scene.naturalHeightForWidth(c, col_widths[col]);
            if (h > row_h) row_h = h;
        }

        // Position row container
        const row_x = content_x + spacing_x;
        const row_w = available_grid_w;
        try scene.layout(r, .{ .x = row_x, .y = current_y, .width = row_w, .height = row_h }, n.id);

        // Position cells in row
        var cell_x = row_x;
        for (cells, 0..) |c, col| {
            if (col >= col_count) break;
            const cw = col_widths[col];
            if (hide_empty and isCellEmpty(c)) {
                cell_x += cw + spacing_x;
                continue;
            }
            try scene.layout(c, .{ .x = cell_x, .y = current_y, .width = cw, .height = row_h }, r.id);
            cell_x += cw + spacing_x;
        }

        current_y += row_h + spacing_y;
    }

    // Layout captions with caption-side: bottom
    for (n.children) |*child| {
        if (isCaption(child) and !caption_top and !child.isOutOfFlow()) {
            const cap_h = scene.naturalHeightForWidth(child, inner_width);
            try scene.layout(child, .{ .x = content_x, .y = current_y, .width = inner_width, .height = cap_h }, n.id);
            current_y += cap_h;
        }
    }
}
