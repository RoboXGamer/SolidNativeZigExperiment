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
        const is_row = std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
        if (is_row) {
            for (n.children) |*child| total = @max(total, naturalHeight(child));
        } else {
            for (n.children) |*child| total += naturalHeight(child);
            if (n.children.len > 1) total += n.style.gap * @as(f32, @floatFromInt(n.children.len - 1));
        }
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
        const pb_val = if (n.style.paddingBottom > 0) n.style.paddingBottom else n.style.padding + (if (std.mem.eql(u8, n.type, "button")) @as(f32, 10) else 0);
        const bb_val = if (n.style.borderBottomWidth > 0) n.style.borderBottomWidth else n.style.borderWidth;
        const mb_val = if (n.style.marginBottom > 0) n.style.marginBottom else n.style.margin;
        const inner_height = @max(0, bounds.height - (pt + bt + mt + pb_val + bb_val + mb_val));

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

        // Flexbox layout
        const is_row = std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
        const wrap = std.mem.eql(u8, n.style.flexWrap, "wrap") or std.mem.eql(u8, n.style.flexWrap, "wrap-reverse");
        const wrap_reverse = std.mem.eql(u8, n.style.flexWrap, "wrap-reverse");
        const gap_main = n.style.gap;
        const main_avail = if (is_row) inner_width else inner_height;
        const nch = n.children.len;
        if (nch == 0) return;

        // order sort indices
        var order_idx: [64]usize = undefined;
        var oi: usize = 0;
        while (oi < nch and oi < 64) : (oi += 1) order_idx[oi] = oi;
        var a: usize = 0;
        while (a < nch) : (a += 1) {
            var bb: usize = a + 1;
            while (bb < nch) : (bb += 1) {
                if (n.children[order_idx[bb]].style.order < n.children[order_idx[a]].style.order) {
                    const tmp = order_idx[a];
                    order_idx[a] = order_idx[bb];
                    order_idx[bb] = tmp;
                }
            }
        }

        // Compute basis and margins for each child
        var bases = std.mem.zeroes([64]f32);
        var grows = std.mem.zeroes([64]f32);
        var shrinks = std.mem.zeroes([64]f32);
        var margins_main = std.mem.zeroes([64]f32);
        var i: usize = 0;
        while (i < nch and i < 64) : (i += 1) {
            const ci = order_idx[i];
            const child = &n.children[ci];
            const cml = if (child.style.marginLeft > 0) child.style.marginLeft else child.style.margin;
            const cmr = if (child.style.marginRight > 0) child.style.marginRight else child.style.margin;
            const cmt = if (child.style.marginTop > 0) child.style.marginTop else child.style.margin;
            const cmb = if (child.style.marginBottom > 0) child.style.marginBottom else child.style.margin;
            const m_main = if (is_row) cml + cmr else cmt + cmb;
            margins_main[i] = m_main;
            const inset = if (is_row) ((if (child.style.paddingLeft > 0) child.style.paddingLeft else child.style.padding) + (if (child.style.borderLeftWidth > 0) child.style.borderLeftWidth else child.style.borderWidth) + (if (child.style.paddingRight > 0) child.style.paddingRight else child.style.padding) + (if (child.style.borderRightWidth > 0) child.style.borderRightWidth else child.style.borderWidth)) else 0;
            const base = if (child.style.flexBasis > 0) child.style.flexBasis else if (is_row and child.style.width > 0) child.style.width else if (!is_row and child.style.height > 0) child.style.height else naturalHeight(child);
            // auto min size
            const auto_min = if (std.mem.eql(u8, child.style.overflow, "visible") and child.style.minWidth == 0 and child.style.minHeight == 0) naturalHeight(child) else 0;
            bases[i] = @max(base + inset, auto_min);
            grows[i] = if (child.style.flexGrow > 0) child.style.flexGrow else 0;
            shrinks[i] = if (child.style.flexShrink > 0) child.style.flexShrink else 1;
        }

        // Wrap children into lines
        var line_starts: [64]usize = undefined;
        var line_crosses = std.mem.zeroes([64]f32);
        var line_count: usize = 0;
        if (wrap) {
            var ls: usize = 0;
            var line_main: f32 = 0;
            var ii: usize = 0;
            while (ii < nch) : (ii += 1) {
                const child_main = bases[ii] + margins_main[ii];
                if (ii > ls and line_main + child_main + gap_main > main_avail) {
                    line_starts[line_count] = ls;
                    line_count += 1;
                    ls = ii;
                    line_main = child_main;
                } else {
                    line_main += child_main + (if (ii > ls) gap_main else 0);
                }
            }
            line_starts[line_count] = ls;
            line_count += 1;
        } else {
            line_starts[0] = 0;
            line_count = 1;
        }
        if (wrap_reverse and line_count > 1) {
            var ri: usize = 0;
            while (ri < line_count / 2) : (ri += 1) {
                const tmp = line_starts[ri];
                line_starts[ri] = line_starts[line_count - 1 - ri];
                line_starts[line_count - 1 - ri] = tmp;
                const tmpc = line_crosses[ri];
                line_crosses[ri] = line_crosses[line_count - 1 - ri];
                line_crosses[line_count - 1 - ri] = tmpc;
            }
        }

        // Pre-pass: compute line_cross for each line
        var li: usize = 0;
        while (li < line_count) : (li += 1) {
            const ls = line_starts[li];
            const le = if (li + 1 < line_count) line_starts[li + 1] else nch;
            var lc: f32 = 0;
            var jj: usize = ls;
            while (jj < le) : (jj += 1) {
                const ci = order_idx[jj];
                lc = @max(lc, naturalHeight(&n.children[ci]));
            }
            line_crosses[li] = lc;
        }

        // align-content: total cross of lines
        var total_cross: f32 = 0;
        var li2: usize = 0;
        while (li2 < line_count) : (li2 += 1) {
            total_cross += line_crosses[li2];
        }
        total_cross += n.style.gap * @as(f32, @floatFromInt(if (line_count > 1) line_count - 1 else 0));
        const cross_avail = if (is_row) inner_height else inner_width;
        var cross_gap = n.style.gap;
        if (std.mem.eql(u8, n.style.alignContent, "space-between") and line_count > 1) {
            cross_gap = n.style.gap + (cross_avail - total_cross) / @as(f32, @floatFromInt(line_count - 1));
        } else if (std.mem.eql(u8, n.style.alignContent, "space-around") and line_count > 1) {
            cross_gap = n.style.gap + (cross_avail - total_cross) / @as(f32, @floatFromInt(line_count));
        } else if (std.mem.eql(u8, n.style.alignContent, "space-evenly") and line_count > 1) {
            cross_gap = n.style.gap + (cross_avail - total_cross) / @as(f32, @floatFromInt(line_count + 1));
        }
        var cross_cursor: f32 = 0;
        if (std.mem.eql(u8, n.style.alignContent, "center")) {
            cross_cursor = (cross_avail - total_cross) * 0.5;
        } else if (std.mem.eql(u8, n.style.alignContent, "flex-end")) {
            cross_cursor = cross_avail - total_cross;
        } else if (std.mem.eql(u8, n.style.alignContent, "space-between") and line_count > 1) {
            cross_cursor = 0;
        } else if (std.mem.eql(u8, n.style.alignContent, "space-around") and line_count > 1) {
            cross_cursor = (cross_avail - total_cross) / @as(f32, @floatFromInt(line_count * 2));
        } else if (std.mem.eql(u8, n.style.alignContent, "space-evenly") and line_count > 1) {
            cross_cursor = (cross_avail - total_cross) / @as(f32, @floatFromInt(line_count + 1));
        }
        if (cross_cursor < 0) cross_cursor = 0;

        // Process each line
        var line_idx: usize = 0;
        while (line_idx < line_count) : (line_idx += 1) {
            const ls = line_starts[line_idx];
            const le = if (line_idx + 1 < line_count) line_starts[line_idx + 1] else nch;
            if (le <= ls) continue;
            const nline = le - ls;
            var line_basis: f32 = 0;
            var line_grow: f32 = 0;
            var line_shrink: f32 = 0;
            var j: usize = ls;
            while (j < le) : (j += 1) {
                line_basis += bases[j] + margins_main[j];
                line_grow += grows[j];
                line_shrink += shrinks[j];
            }
            line_basis += gap_main * @as(f32, @floatFromInt(nline - 1));
            const line_free = main_avail - line_basis;

            var sizes = std.mem.zeroes([64]f32);
            var j2: usize = ls;
            while (j2 < le) : (j2 += 1) {
                sizes[j2] = bases[j2];
                if (line_free > 0 and line_grow > 0 and grows[j2] > 0) {
                    sizes[j2] += line_free * grows[j2] / line_grow;
                } else if (line_free < 0 and line_shrink > 0) {
                    sizes[j2] += line_free * shrinks[j2] / line_shrink;
                    if (sizes[j2] < 0) sizes[j2] = 0;
                }
            }

            var line_gap = gap_main;
            var line_cursor: f32 = 0;
            if (std.mem.eql(u8, n.style.justifyContent, "center")) {
                line_cursor = line_free * 0.5;
            } else if (std.mem.eql(u8, n.style.justifyContent, "flex-end")) {
                line_cursor = line_free;
            } else if (std.mem.eql(u8, n.style.justifyContent, "space-between") and nline > 1) {
                line_gap = gap_main + line_free / @as(f32, @floatFromInt(nline - 1));
            } else if (std.mem.eql(u8, n.style.justifyContent, "space-around") and nline > 1) {
                line_cursor = line_free / @as(f32, @floatFromInt(nline * 2));
                line_gap = gap_main + line_free / @as(f32, @floatFromInt(nline));
            } else if (std.mem.eql(u8, n.style.justifyContent, "space-evenly") and nline > 1) {
                line_cursor = line_free / @as(f32, @floatFromInt(nline + 1));
                line_gap = gap_main + line_free / @as(f32, @floatFromInt(nline + 1));
            }
            if (line_cursor < 0) line_cursor = 0;

            const line_cross = line_crosses[line_idx];

            var j3: usize = ls;
            while (j3 < le) : (j3 += 1) {
                const ci = order_idx[j3];
                const child = &n.children[ci];
                const cml = if (child.style.marginLeft > 0) child.style.marginLeft else child.style.margin;
                const cmt = if (child.style.marginTop > 0) child.style.marginTop else child.style.margin;
                const cmr = if (child.style.marginRight > 0) child.style.marginRight else child.style.margin;
                const cmb = if (child.style.marginBottom > 0) child.style.marginBottom else child.style.margin;
                const child_h = naturalHeight(child);
                const sz = sizes[j3];
                const algn = if (std.mem.eql(u8, child.style.alignSelf, "auto")) n.style.alignItems else child.style.alignSelf;
                var cross_offset: f32 = 0;
                if (std.mem.eql(u8, algn, "center")) {
                    cross_offset = (line_cross - child_h) * 0.5;
                } else if (std.mem.eql(u8, algn, "flex-end")) {
                    cross_offset = line_cross - child_h;
                } else if (std.mem.eql(u8, algn, "baseline")) {
                    var max_base: f32 = 0;
                    var bk: usize = ls;
                    while (bk < le) : (bk += 1) {
                        const ci2 = order_idx[bk];
                        const ch2 = &n.children[ci2];
                        const base2 = if (std.mem.eql(u8, ch2.type, "text")) (if (ch2.style.fontSize > 0) ch2.style.fontSize * 0.8 else 16) else 0;
                        if (base2 > max_base) max_base = base2;
                    }
                    const child_base = if (std.mem.eql(u8, child.type, "text")) (if (child.style.fontSize > 0) child.style.fontSize * 0.8 else 16) else 0;
                    cross_offset = max_base - child_base;
                }
                const x = if (is_row) (bounds.x + pl + bl + ml + line_cursor + cml) else (bounds.x + pl + bl + ml + cross_offset);
                const y = if (is_row) (bounds.y + pt + bt + mt + cross_cursor + cross_offset) else (bounds.y + pt + bt + mt + line_cursor + cmt);
                const w = if (is_row) sz else inner_width;
                const h = if (is_row) child_h else sz;
                const cb = Rect{ .x = x, .y = y, .width = w, .height = h };
                try self.layout(child, cb, n.id);
                line_cursor += sz + (if (is_row) (cml + cmr) else (cmt + cmb)) + line_gap;
            }
            cross_cursor += line_cross + cross_gap;
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

test "per-side padding and border affect layout" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"paddingTop":5,"paddingLeft":2,"margin":4},"children":[{"id":3,"type":"text","text":"hi"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expect(b.x > 0);
    try std.testing.expect(b.width <= 300);
}

test "min/max and aspect ratio constraints" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"minWidth":50,"maxWidth":100,"aspectRatio":2},"children":[]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expect(b.width >= 50 and b.width <= 100);
    try std.testing.expect(b.height > 0);
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