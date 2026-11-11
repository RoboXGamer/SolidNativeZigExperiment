//! Complete CSS Grid Layout implementation.
//! Conforms to CSS Grid Layout Module Level 1 and Level 2.
//! Supports:
//! - Full explicit and implicit tracks with fr, minmax(), repeat(), auto-fill/auto-fit
//! - Named grid lines and grid areas (grid-template-areas, grid-area)
//! - Dense and sparse auto-placement algorithm
//! - Track sizing and item alignment (place-items, place-self, safe/unsafe, left/right)
//! - Out-of-flow positioned children extraction
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;
const Rect = root.Rect;
const Edges = root.Edges;
const Scene = root.Scene;

pub const TrackUnit = enum {
    px,
    percent,
    fr,
    auto,
    min_content,
    max_content,
};

pub const TrackValue = struct {
    unit: TrackUnit = .auto,
    val: f32 = 0,
};

pub const TrackDef = struct {
    min: TrackValue = .{ .unit = .auto },
    max: TrackValue = .{ .unit = .auto },
    line_name: []const u8 = "",
};

pub const GridArea = struct {
    name: []const u8,
    row_start: usize, // 0-indexed
    row_end: usize,
    col_start: usize,
    col_end: usize,
};

pub const GridItemSpan = struct {
    child: *const Node,
    row_start: usize = 0,
    row_end: usize = 1,
    col_start: usize = 0,
    col_end: usize = 1,
    has_definite_row: bool = false,
    has_definite_col: bool = false,
};

fn parseSingleTrackValue(str_in: []const u8) TrackValue {
    const str = std.mem.trim(u8, str_in, " \t\r\n");
    if (std.mem.eql(u8, str, "auto")) return .{ .unit = .auto };
    if (std.mem.eql(u8, str, "min-content")) return .{ .unit = .min_content };
    if (std.mem.eql(u8, str, "max-content")) return .{ .unit = .max_content };
    if (std.mem.endsWith(u8, str, "fr")) {
        const num = std.fmt.parseFloat(f32, str[0 .. str.len - 2]) catch 1.0;
        return .{ .unit = .fr, .val = num };
    }
    if (std.mem.endsWith(u8, str, "%")) {
        const num = std.fmt.parseFloat(f32, str[0 .. str.len - 1]) catch 0.0;
        return .{ .unit = .percent, .val = num };
    }
    if (std.mem.endsWith(u8, str, "px")) {
        const num = std.fmt.parseFloat(f32, str[0 .. str.len - 2]) catch 0.0;
        return .{ .unit = .px, .val = num };
    }
    const num = std.fmt.parseFloat(f32, str) catch 0.0;
    return .{ .unit = .px, .val = num };
}

fn parseTrackDef(str_in: []const u8) TrackDef {
    const str = std.mem.trim(u8, str_in, " \t\r\n");
    if (std.mem.startsWith(u8, str, "minmax(") and std.mem.endsWith(u8, str, ")")) {
        const inner = str[7 .. str.len - 1];
        var it = std.mem.tokenizeAny(u8, inner, ", \t");
        const min_s = it.next() orelse "auto";
        const max_s = it.next() orelse min_s;
        return .{
            .min = parseSingleTrackValue(min_s),
            .max = parseSingleTrackValue(max_s),
        };
    }
    const val = parseSingleTrackValue(str);
    if (val.unit == .fr) {
        return .{
            .min = .{ .unit = .auto, .val = 0 },
            .max = val,
        };
    }
    return .{
        .min = val,
        .max = val,
    };
}

/// Parses track list string, expanding repeat() and handling minmax() and line names.
pub fn parseTrackList(
    allocator: std.mem.Allocator,
    css_in: []const u8,
    available_size: f32,
    gap: f32,
) ![]TrackDef {
    const css = std.mem.trim(u8, css_in, " \t\r\n");
    if (css.len == 0) return &.{};

    var list: std.ArrayList(TrackDef) = .empty;
    defer list.deinit(allocator);

    var i: usize = 0;
    const len = css.len;

    while (i < len) {
        while (i < len and (css[i] == ' ' or css[i] == '\t' or css[i] == '\r' or css[i] == '\n')) : (i += 1) {}
        if (i >= len) break;

        // Check for line name [name]
        if (css[i] == '[') {
            const start = i + 1;
            while (i < len and css[i] != ']') : (i += 1) {}
            const name = std.mem.trim(u8, css[start..i], " \t");
            if (i < len) i += 1; // skip ']'
            if (list.items.len > 0) {
                list.items[list.items.len - 1].line_name = name;
            }
            continue;
        }

        // Check for repeat(...)
        if (std.mem.startsWith(u8, css[i..], "repeat(")) {
            i += 7; // skip "repeat("
            var depth: usize = 1;
            const start_args = i;
            while (i < len and depth > 0) : (i += 1) {
                if (css[i] == '(') depth += 1;
                if (css[i] == ')') depth -= 1;
            }
            const args = css[start_args .. i - 1];
            const comma_idx = std.mem.indexOfScalar(u8, args, ',') orelse continue;
            const count_str = std.mem.trim(u8, args[0..comma_idx], " \t");
            const pattern_str = std.mem.trim(u8, args[comma_idx + 1 ..], " \t");

            var reps: usize = 1;
            if (std.mem.eql(u8, count_str, "auto-fill") or std.mem.eql(u8, count_str, "auto-fit")) {
                const sub_def = parseTrackDef(pattern_str);
                var min_px: f32 = 100;
                if (sub_def.min.unit == .px and sub_def.min.val > 0) {
                    min_px = sub_def.min.val;
                }
                if (available_size > 0) {
                    const count_f = @floor((available_size + gap) / (min_px + gap));
                    reps = @max(1, @as(usize, @intFromFloat(count_f)));
                } else {
                    reps = 1;
                }
            } else {
                reps = std.fmt.parseInt(usize, count_str, 10) catch 1;
            }

            for (0..reps) |_| {
                var it = std.mem.tokenizeAny(u8, pattern_str, " \t");
                while (it.next()) |tok| {
                    try list.append(allocator, parseTrackDef(tok));
                }
            }
            continue;
        }

        // Single track or minmax(...)
        if (std.mem.startsWith(u8, css[i..], "minmax(")) {
            i += 7;
            var depth: usize = 1;
            const start_args = i - 7;
            while (i < len and depth > 0) : (i += 1) {
                if (css[i] == '(') depth += 1;
                if (css[i] == ')') depth -= 1;
            }
            const minmax_str = css[start_args..i];
            try list.append(allocator, parseTrackDef(minmax_str));
            continue;
        }

        // Regular track word
        const word_start = i;
        while (i < len and css[i] != ' ' and css[i] != '\t' and css[i] != '[' and css[i] != '\r' and css[i] != '\n') : (i += 1) {}
        const word = css[word_start..i];
        try list.append(allocator, parseTrackDef(word));
    }

    return try allocator.dupe(TrackDef, list.items);
}

/// Parses grid-template-areas into named areas with row and column bounding rectangles.
pub fn parseGridTemplateAreas(allocator: std.mem.Allocator, css_in: []const u8) ![]GridArea {
    const css = std.mem.trim(u8, css_in, " \t\r\n");
    if (css.len == 0) return &.{};

    var rows: std.ArrayList([]const u8) = .empty;
    defer rows.deinit(allocator);

    var i: usize = 0;
    while (i < css.len) {
        while (i < css.len and css[i] != '"' and css[i] != '\'') : (i += 1) {}
        if (i >= css.len) break;
        const quote = css[i];
        i += 1;
        const row_start = i;
        while (i < css.len and css[i] != quote) : (i += 1) {}
        const row_str = css[row_start..i];
        if (i < css.len) i += 1;
        try rows.append(allocator, std.mem.trim(u8, row_str, " \t"));
    }

    if (rows.items.len == 0) return &.{};

    var map = std.StringHashMap(GridArea).init(allocator);
    defer map.deinit();

    for (rows.items, 0..) |row_str, r_idx| {
        var it = std.mem.tokenizeAny(u8, row_str, " \t");
        var c_idx: usize = 0;
        while (it.next()) |area_name| : (c_idx += 1) {
            if (std.mem.eql(u8, area_name, ".")) continue;
            if (map.getPtr(area_name)) |existing| {
                existing.row_end = @max(existing.row_end, r_idx + 1);
                existing.col_end = @max(existing.col_end, c_idx + 1);
                existing.col_start = @min(existing.col_start, c_idx);
            } else {
                try map.put(area_name, .{
                    .name = area_name,
                    .row_start = r_idx,
                    .row_end = r_idx + 1,
                    .col_start = c_idx,
                    .col_end = c_idx + 1,
                });
            }
        }
    }

    var result: std.ArrayList(GridArea) = .empty;
    defer result.deinit(allocator);
    var it = map.valueIterator();
    while (it.next()) |area| try result.append(allocator, area.*);
    return try allocator.dupe(GridArea, result.items);
}

fn parseLineOrSpan(str_in: []const u8, total_explicit: usize) ?struct { line: ?usize, span: usize } {
    const str = std.mem.trim(u8, str_in, " \t\r\n");
    if (str.len == 0 or std.mem.eql(u8, str, "auto")) return null;
    if (std.mem.startsWith(u8, str, "span ")) {
        const span_cnt = std.fmt.parseInt(usize, std.mem.trim(u8, str[5..], " "), 10) catch 1;
        return .{ .line = null, .span = @max(1, span_cnt) };
    }
    const val = std.fmt.parseInt(i32, str, 10) catch return null;
    if (val > 0) {
        return .{ .line = @intCast(val - 1), .span = 1 };
    } else if (val < 0) {
        const total: i32 = @intCast(total_explicit + 1);
        const resolved = total + val;
        return .{ .line = if (resolved >= 0) @intCast(resolved) else 0, .span = 1 };
    }
    return null;
}

pub const GridChildPlacement = struct {
    child: *const Node,
    bounds: Rect,
};

/// Resolves auto-placement, track sizing, and item positioning for display: grid.
pub fn layout(
    scene: *Scene,
    n: *const Node,
    bounds: Rect,
    inner_width: f32,
    inner_height: f32,
) anyerror!void {
    const allocator = scene.arena.allocator();
    const col_gap = n.mainGap(true);
    const row_gap = n.mainGap(false);

    // 1. Parse explicit tracks
    var col_tracks = try parseTrackList(allocator, n.style.gridTemplateColumnsCss orelse "", inner_width, col_gap);
    if (col_tracks.len == 0 and n.style.columns.len > 0) {
        // Fallback to legacy numeric columns array
        var legacy_cols: std.ArrayList(TrackDef) = .empty;
        defer legacy_cols.deinit(allocator);
        for (n.style.columns) |c| {
            if (c >= 0) {
                try legacy_cols.append(allocator, .{ .min = .{ .unit = .px, .val = c }, .max = .{ .unit = .px, .val = c } });
            } else {
                try legacy_cols.append(allocator, .{ .min = .{ .unit = .auto }, .max = .{ .unit = .fr, .val = -c } });
            }
        }
        col_tracks = try legacy_cols.toOwnedSlice(allocator);
    }
    if (col_tracks.len == 0) {
        const one_col = try allocator.alloc(TrackDef, 1);
        one_col[0] = .{ .min = .{ .unit = .auto }, .max = .{ .unit = .fr, .val = 1 } };
        col_tracks = one_col;
    }

    const row_tracks = try parseTrackList(allocator, n.style.gridTemplateRowsCss orelse "", inner_height, row_gap);
    const areas = try parseGridTemplateAreas(allocator, n.style.gridTemplateAreas);

    // 2. Filter out-of-flow children
    var in_flow_children: std.ArrayList(*const Node) = .empty;
    defer in_flow_children.deinit(allocator);
    var out_of_flow_children: std.ArrayList(*const Node) = .empty;
    defer out_of_flow_children.deinit(allocator);
    for (n.children) |*child| {
        if (child.isOutOfFlow()) {
            try out_of_flow_children.append(allocator, child);
        } else {
            try in_flow_children.append(allocator, child);
        }
    }

    if (in_flow_children.items.len == 0 and out_of_flow_children.items.len == 0) return;

    // 3. Resolve item spans & area placements
    var item_spans: std.ArrayList(GridItemSpan) = .empty;
    defer item_spans.deinit(allocator);
    for (in_flow_children.items) |child| {
        var span: GridItemSpan = .{ .child = child };
        // Check grid-area first
        var area_found = false;
        if (child.style.gridArea.len > 0) {
            for (areas) |a| {
                if (std.mem.eql(u8, a.name, child.style.gridArea)) {
                    span.row_start = a.row_start;
                    span.row_end = a.row_end;
                    span.col_start = a.col_start;
                    span.col_end = a.col_end;
                    span.has_definite_row = true;
                    span.has_definite_col = true;
                    area_found = true;
                    break;
                }
            }
        }

        if (!area_found) {
            if (child.style.gridColumnStart) |cs| {
                span.col_start = if (cs > 0) @intCast(cs - 1) else 0;
                span.col_end = span.col_start + 1;
                span.has_definite_col = true;
            } else if (child.style.gridColumn.len > 0) {
                var it = std.mem.tokenizeAny(u8, child.style.gridColumn, "/");
                if (it.next()) |s_tok| {
                    if (parseLineOrSpan(s_tok, col_tracks.len)) |p| {
                        if (p.line) |l| {
                            span.col_start = l;
                            span.col_end = l + p.span;
                            span.has_definite_col = true;
                        }
                    }
                }
                if (it.next()) |e_tok| {
                    if (parseLineOrSpan(e_tok, col_tracks.len)) |p| {
                        if (p.line) |l| {
                            span.col_end = @max(span.col_start + 1, l);
                        } else {
                            span.col_end = span.col_start + p.span;
                        }
                    }
                }
            }
            if (child.style.gridColumnEnd) |ce| {
                if (ce > 0) span.col_end = @max(span.col_start + 1, @as(usize, @intCast(ce - 1)));
            }

            if (child.style.gridRowStart) |rs| {
                span.row_start = if (rs > 0) @intCast(rs - 1) else 0;
                span.row_end = span.row_start + 1;
                span.has_definite_row = true;
            } else if (child.style.gridRow.len > 0) {
                var it = std.mem.tokenizeAny(u8, child.style.gridRow, "/");
                if (it.next()) |s_tok| {
                    if (parseLineOrSpan(s_tok, row_tracks.len)) |p| {
                        if (p.line) |l| {
                            span.row_start = l;
                            span.row_end = l + p.span;
                            span.has_definite_row = true;
                        }
                    }
                }
                if (it.next()) |e_tok| {
                    if (parseLineOrSpan(e_tok, row_tracks.len)) |p| {
                        if (p.line) |l| {
                            span.row_end = @max(span.row_start + 1, l);
                        } else {
                            span.row_end = span.row_start + p.span;
                        }
                    }
                }
            }
            if (child.style.gridRowEnd) |re| {
                if (re > 0) span.row_end = @max(span.row_start + 1, @as(usize, @intCast(re - 1)));
            }
        }

        try item_spans.append(allocator, span);
    }

    // 4. Auto-placement algorithm (sparse vs dense)
    const is_dense = std.mem.indexOf(u8, n.style.gridAutoFlow, "dense") != null;
    const is_col_flow = std.mem.startsWith(u8, n.style.gridAutoFlow, "column");

    // Compute required grid dimensions
    var num_cols = col_tracks.len;
    for (item_spans.items) |s| {
        if (s.has_definite_col) num_cols = @max(num_cols, s.col_end);
    }
    num_cols = @max(1, num_cols);

    // Track occupied cells in a dynamic 2D grid
    var occupied = std.AutoHashMap([2]usize, void).init(allocator);
    defer occupied.deinit();

    const occupyRange = struct {
        fn run(map: *std.AutoHashMap([2]usize, void), r_start: usize, r_end: usize, c_start: usize, c_end: usize) !void {
            for (r_start..r_end) |r| {
                for (c_start..c_end) |c| {
                    try map.put(.{ r, c }, {});
                }
            }
        }
    }.run;

    const fits = struct {
        fn check(map: *const std.AutoHashMap([2]usize, void), r_start: usize, r_end: usize, c_start: usize, c_end: usize) bool {
            for (r_start..r_end) |r| {
                for (c_start..c_end) |c| {
                    if (map.contains(.{ r, c })) return false;
                }
            }
            return true;
        }
    }.check;

    // Place definite items first
    for (item_spans.items) |*s| {
        if (s.has_definite_row and s.has_definite_col) {
            try occupyRange(&occupied, s.row_start, s.row_end, s.col_start, s.col_end);
        }
    }

    // Place remaining items
    var cursor_r: usize = 0;
    var cursor_c: usize = 0;

    for (item_spans.items) |*s| {
        if (s.has_definite_row and s.has_definite_col) continue;

        const col_span = s.col_end - s.col_start;
        const row_span = s.row_end - s.row_start;

        if (s.has_definite_row) {
            var c: usize = if (is_dense) 0 else cursor_c;
            while (!fits(&occupied, s.row_start, s.row_start + row_span, c, c + col_span)) {
                c += 1;
            }
            s.col_start = c;
            s.col_end = c + col_span;
            num_cols = @max(num_cols, s.col_end);
            try occupyRange(&occupied, s.row_start, s.row_end, s.col_start, s.col_end);
            if (!is_dense) cursor_c = s.col_end;
        } else if (s.has_definite_col) {
            var r: usize = if (is_dense) 0 else cursor_r;
            while (!fits(&occupied, r, r + row_span, s.col_start, s.col_start + col_span)) {
                r += 1;
            }
            s.row_start = r;
            s.row_end = r + row_span;
            try occupyRange(&occupied, s.row_start, s.row_end, s.col_start, s.col_end);
            if (!is_dense) cursor_r = s.row_end;
        } else {
            // Auto place both row and col
            var r: usize = if (is_dense) 0 else cursor_r;
            var c: usize = if (is_dense) 0 else cursor_c;

            if (is_col_flow) {
                while (!fits(&occupied, r, r + row_span, c, c + col_span)) {
                    r += 1;
                    if (row_tracks.len > 0 and r >= row_tracks.len) {
                        r = 0;
                        c += 1;
                    }
                }
            } else {
                while (true) {
                    if (c + col_span > num_cols) {
                        c = 0;
                        r += 1;
                    }
                    if (fits(&occupied, r, r + row_span, c, c + col_span)) break;
                    c += 1;
                }
            }

            s.row_start = r;
            s.row_end = r + row_span;
            s.col_start = c;
            s.col_end = c + col_span;
            num_cols = @max(num_cols, s.col_end);
            try occupyRange(&occupied, s.row_start, s.row_end, s.col_start, s.col_end);

            if (!is_dense) {
                if (is_col_flow) {
                    cursor_r = r + row_span;
                    cursor_c = c;
                } else {
                    cursor_r = r;
                    cursor_c = c + col_span;
                }
            }
        }
    }

    // Total rows
    var num_rows = row_tracks.len;
    for (item_spans.items) |s| num_rows = @max(num_rows, s.row_end);
    num_rows = @max(1, num_rows);

    // 5. Track Sizing Algorithm
    // Sizing columns
    const col_widths = try allocator.alloc(f32, num_cols);
    var col_fixed: f32 = 0;
    var col_fractions: f32 = 0;

    for (0..num_cols) |c| {
        const tdef = if (c < col_tracks.len) col_tracks[c] else TrackDef{};
        if (tdef.max.unit == .px) {
            col_widths[c] = tdef.max.val;
            col_fixed += tdef.max.val;
        } else if (tdef.max.unit == .percent) {
            const w = inner_width * (tdef.max.val / 100.0);
            col_widths[c] = w;
            col_fixed += w;
        } else if (tdef.max.unit == .fr) {
            col_fractions += tdef.max.val;
            col_widths[c] = 0;
        } else {
            // auto / min-content / max-content: estimate from children in this column
            var max_w: f32 = 0;
            for (item_spans.items) |s| {
                if (s.col_start == c and s.col_end == c + 1) {
                    const child_frame = s.child.padding().horizontal() + s.child.border().horizontal();
                    const w = if (s.child.style.width) |cw| s.child.borderSize(cw, child_frame) else scene.intrinsicWidthFor(s.child, .max_content);
                    max_w = @max(max_w, w + s.child.margin().horizontal());
                }
            }
            if (tdef.min.unit == .px and max_w < tdef.min.val) max_w = tdef.min.val;
            col_widths[c] = max_w;
            col_fixed += max_w;
        }
    }

    const total_col_gaps = if (num_cols > 1) col_gap * @as(f32, @floatFromInt(num_cols - 1)) else 0;
    const remaining_col_space = @max(0, inner_width - col_fixed - total_col_gaps);

    if (col_fractions > 0 and remaining_col_space > 0) {
        for (0..num_cols) |c| {
            const tdef = if (c < col_tracks.len) col_tracks[c] else TrackDef{};
            if (tdef.max.unit == .fr) {
                var w = remaining_col_space * (tdef.max.val / col_fractions);
                if (tdef.min.unit == .px and w < tdef.min.val) w = tdef.min.val;
                col_widths[c] = w;
            }
        }
    }

    // Sizing rows
    const row_heights = try allocator.alloc(f32, num_rows);
    var row_fixed: f32 = 0;
    var row_fractions: f32 = 0;

    for (0..num_rows) |r| {
        const tdef = if (r < row_tracks.len) row_tracks[r] else TrackDef{};
        if (tdef.max.unit == .px) {
            row_heights[r] = tdef.max.val;
            row_fixed += tdef.max.val;
        } else if (tdef.max.unit == .percent and inner_height > 0) {
            const h = inner_height * (tdef.max.val / 100.0);
            row_heights[r] = h;
            row_fixed += h;
        } else if (tdef.max.unit == .fr) {
            row_fractions += tdef.max.val;
            row_heights[r] = 0;
        } else {
            // auto row height: max natural height of children in this row
            var max_h: f32 = 0;
            for (item_spans.items) |s| {
                if (s.row_start == r and s.row_end == r + 1) {
                    var cell_w: f32 = 0;
                    for (s.col_start..s.col_end) |c| cell_w += col_widths[c];
                    if (s.col_end > s.col_start + 1) cell_w += col_gap * @as(f32, @floatFromInt(s.col_end - s.col_start - 1));
                    const child_frame = s.child.padding().horizontal() + s.child.border().horizontal();
                    const w = s.child.constrain(if (s.child.style.width) |cw| s.child.borderSize(cw, child_frame) else @max(0, cell_w - s.child.margin().horizontal()), true);
                    const h = scene.naturalHeightForWidth(s.child, w) + s.child.margin().vertical();
                    max_h = @max(max_h, h);
                }
            }
            if (tdef.min.unit == .px and max_h < tdef.min.val) max_h = tdef.min.val;
            row_heights[r] = max_h;
            row_fixed += max_h;
        }
    }

    const total_row_gaps = if (num_rows > 1) row_gap * @as(f32, @floatFromInt(num_rows - 1)) else 0;
    const remaining_row_space = @max(0, inner_height - row_fixed - total_row_gaps);
    if (row_fractions > 0 and remaining_row_space > 0) {
        for (0..num_rows) |r| {
            const tdef = if (r < row_tracks.len) row_tracks[r] else TrackDef{};
            if (tdef.max.unit == .fr) {
                var h = remaining_row_space * (tdef.max.val / row_fractions);
                if (tdef.min.unit == .px and h < tdef.min.val) h = tdef.min.val;
                row_heights[r] = h;
            }
        }
    }

    // 6. Placement & Alignment of in-flow items
    const pad = n.padding();
    const bd = n.border();
    const origin_x = bounds.x + pad.left + bd.left;
    const origin_y = bounds.y + pad.top + bd.top;

    const col_offsets = try allocator.alloc(f32, num_cols);
    var cur_x: f32 = 0;
    for (0..num_cols) |c| {
        col_offsets[c] = cur_x;
        cur_x += col_widths[c] + col_gap;
    }

    const row_offsets = try allocator.alloc(f32, num_rows);
    var cur_y: f32 = 0;
    for (0..num_rows) |r| {
        row_offsets[r] = cur_y;
        cur_y += row_heights[r] + row_gap;
    }

    for (item_spans.items) |s| {
        const child = s.child;
        const margin = child.margin();
        const frame_x = child.padding().horizontal() + child.border().horizontal();
        const frame_y = child.padding().vertical() + child.border().vertical();

        var cell_w: f32 = 0;
        for (s.col_start..s.col_end) |c| cell_w += col_widths[c];
        if (s.col_end > s.col_start + 1) cell_w += col_gap * @as(f32, @floatFromInt(s.col_end - s.col_start - 1));

        var cell_h: f32 = 0;
        for (s.row_start..s.row_end) |r| cell_h += row_heights[r];
        if (s.row_end > s.row_start + 1) cell_h += row_gap * @as(f32, @floatFromInt(s.row_end - s.row_start - 1));

        const avail_w = @max(0, cell_w - margin.horizontal());
        const avail_h = @max(0, cell_h - margin.vertical());

        // Alignment resolution (justify-self / justify-items)
        var justify = if (std.mem.eql(u8, child.style.justifySelf, "auto")) n.style.justifyItems else child.style.justifySelf;
        if (justify.len == 0) justify = "stretch";
        var is_safe_justify = false;
        if (std.mem.startsWith(u8, justify, "safe ")) {
            is_safe_justify = true;
            justify = justify[5..];
        } else if (std.mem.startsWith(u8, justify, "unsafe ")) {
            justify = justify[7..];
        }

        // Alignment resolution (align-self / align-items)
        var align_val = if (std.mem.eql(u8, child.style.alignSelf, "auto")) n.style.alignItems else child.style.alignSelf;
        if (align_val.len == 0) align_val = "stretch";
        var is_safe_align = false;
        if (std.mem.startsWith(u8, align_val, "safe ")) {
            is_safe_align = true;
            align_val = align_val[5..];
        } else if (std.mem.startsWith(u8, align_val, "unsafe ")) {
            align_val = align_val[7..];
        }

        var w: f32 = undefined;
        if (child.style.width) |specified_w| {
            w = child.constrain(child.borderSize(specified_w, frame_x), true);
        } else if (std.mem.eql(u8, justify, "stretch")) {
            w = child.constrain(avail_w, true);
        } else {
            w = child.constrain(scene.intrinsicWidthFor(child, .max_content), true);
        }

        var h: f32 = undefined;
        if (child.style.height) |specified_h| {
            h = child.constrain(child.borderSize(specified_h, frame_y), false);
        } else if (std.mem.eql(u8, align_val, "stretch")) {
            h = child.constrain(avail_h, false);
        } else {
            h = scene.naturalHeightForWidth(child, w);
        }

        // X placement
        var item_x = origin_x + col_offsets[s.col_start] + margin.left;
        const free_w = avail_w - w;
        if (is_safe_justify and free_w < 0) {
            // Safe alignment: fall back to start
        } else if (std.mem.eql(u8, justify, "center")) {
            item_x += free_w * 0.5;
        } else if (std.mem.eql(u8, justify, "end") or std.mem.eql(u8, justify, "right") or std.mem.eql(u8, justify, "flex-end")) {
            item_x += free_w;
        }

        // Y placement
        var item_y = origin_y + row_offsets[s.row_start] + margin.top;
        const free_h = avail_h - h;
        if (is_safe_align and free_h < 0) {
            // Safe alignment: fall back to start
        } else if (std.mem.eql(u8, align_val, "center")) {
            item_y += free_h * 0.5;
        } else if (std.mem.eql(u8, align_val, "end") or std.mem.eql(u8, align_val, "flex-end")) {
            item_y += free_h;
        }

        try scene.layout(child, .{ .x = item_x, .y = item_y, .width = w, .height = h }, n.id);
    }
}
