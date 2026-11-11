//! CSS flexbox layout: intrinsic sizing, flex-basis resolution and auto margins.
//!
//! Intrinsic sizes come from the scene's text metrics (`Scene.text`), so real
//! backend font measurement flows into min/max-content sizing and `flex-basis:
//! content` instead of a per-character estimate.
//!
//! Margin values use `auto_margin` (-1) as the "auto" sentinel (the JS bridge
//! serializes `margin: "auto"` to it). `flexBasis` uses -1 for `auto`, -2 for
//! `content` and values >= 0 for explicit main-axis sizes.
const std = @import("std");
const root = @import("root.zig");
pub const auto_margin = root.auto_margin;
const Node = root.Node;
const Rect = root.Rect;
const Scene = root.Scene;

const ItemInfo = struct {
    child: *const Node,
    // Margins from the node's margin ring, auto sentinel preserved.
    mt: f32 = 0,
    mr: f32 = 0,
    mb: f32 = 0,
    ml: f32 = 0,
    // Flex properties.
    base_main: f32 = 0, // hypothetical main size (border box)
    main_size: f32 = 0, // resolved main size (border box)
    cross_size: f32 = 0, // resolved cross size (border box)
    grow: f32 = 0,
    shrink: f32 = 1,
    min_main: f32 = 0,
    max_main: f32 = std.math.inf(f32),
    // Non-auto margins, already resolved.
    main_before: f32 = 0,
    main_after: f32 = 0,
    cross_before: f32 = 0,
    cross_after: f32 = 0,
    main_before_auto: bool = false,
    main_after_auto: bool = false,
    cross_before_auto: bool = false,
    cross_after_auto: bool = false,
};

fn isAuto(v: f32) bool {
    return v == auto_margin;
}

fn fixed(v: f32) f32 {
    return if (v == auto_margin) 0 else v;
}

fn isRowFlex(n: *const Node) bool {
    return std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
}

fn frameWidth(n: *const Node) f32 {
    return n.padding().horizontal() + n.border().horizontal();
}

/// Content height (border box, excludes the node's own margins).
fn contentHeight(scene: *const Scene, n: *const Node) f32 {
    if (n.style.height > 0) return n.style.height;
    return scene.naturalHeight(n);
}

/// Max-content width (border box) measured with the backend text metrics.
fn maxContentWidth(scene: *const Scene, n: *const Node) f32 {
    if (n.style.width > 0) return n.style.width;
    if (std.mem.eql(u8, n.type, "text")) return scene.text.maxContentWidth(n.text, n.fontSize()) + frameWidth(n);
    var inner: f32 = 0;
    if (isRowFlex(n)) {
        for (n.children, 0..) |*c, i| {
            if (i > 0) inner += n.style.gap;
            inner += maxContentWidth(scene, c);
        }
    } else {
        for (n.children) |*c| {
            const w = maxContentWidth(scene, c);
            if (w > inner) inner = w;
        }
    }
    return inner + frameWidth(n);
}

/// Min-content width (border box): widest unbreakable word, recursively.
fn minContentWidth(scene: *const Scene, n: *const Node) f32 {
    if (n.style.width > 0) return n.style.width;
    if (std.mem.eql(u8, n.type, "text")) return scene.text.minContentWidth(n.text, n.fontSize()) + frameWidth(n);
    var inner: f32 = 0;
    if (isRowFlex(n)) {
        for (n.children, 0..) |*c, i| {
            if (i > 0) inner += n.style.gap;
            inner += minContentWidth(scene, c);
        }
    } else {
        for (n.children) |*c| {
            const w = minContentWidth(scene, c);
            if (w > inner) inner = w;
        }
    }
    return inner + frameWidth(n);
}

fn hypotheticalCross(scene: *const Scene, child: *const Node, is_row: bool) f32 {
    if (is_row) {
        return if (child.style.height > 0) child.style.height else contentHeight(scene, child);
    }
    return if (child.style.width > 0) child.style.width else maxContentWidth(scene, child);
}

fn clampCross(child: *const Node, is_row: bool, v: f32) f32 {
    var s = v;
    if (is_row) {
        if (child.style.minHeight > 0 and s < child.style.minHeight) s = child.style.minHeight;
        if (child.style.maxHeight > 0 and s > child.style.maxHeight) s = child.style.maxHeight;
    } else {
        if (child.style.minWidth > 0 and s < child.style.minWidth) s = child.style.minWidth;
        if (child.style.maxWidth > 0 and s > child.style.maxWidth) s = child.style.maxWidth;
    }
    return s;
}

fn resolveMainBasis(scene: *const Scene, child: *const Node, is_row: bool) f32 {
    const b = child.style.flexBasis;
    if (b >= 0) return b; // explicit basis (border box in this engine)
    if (b == -2) return if (is_row) maxContentWidth(scene, child) else contentHeight(scene, child);
    // flex-basis: auto -> main size property, else content size.
    if (is_row) {
        return if (child.style.width > 0) child.style.width else maxContentWidth(scene, child);
    }
    return if (child.style.height > 0) child.style.height else contentHeight(scene, child);
}

fn minMainSize(scene: *const Scene, child: *const Node, is_row: bool) f32 {
    // CSS min-width/min-height: auto resolves to the content-based minimum
    // for overflow: visible items, otherwise zero.
    if (is_row) {
        if (child.style.minWidth > 0) return child.style.minWidth;
        if (std.mem.eql(u8, child.style.overflow, "visible")) return minContentWidth(scene, child);
        return 0;
    }
    if (child.style.minHeight > 0) return child.style.minHeight;
    if (std.mem.eql(u8, child.style.overflow, "visible")) return contentHeight(scene, child);
    return 0;
}

fn maxMainSize(child: *const Node, is_row: bool) f32 {
    if (is_row) return if (child.style.maxWidth > 0) child.style.maxWidth else std.math.inf(f32);
    return if (child.style.maxHeight > 0) child.style.maxHeight else std.math.inf(f32);
}

fn alignOf(container: *const Node, child: *const Node) []const u8 {
    if (std.mem.eql(u8, child.style.alignSelf, "auto")) return container.style.alignItems;
    return child.style.alignSelf;
}

/// Baseline offset from the top of the line box, from real font ascent.
fn baselineOf(scene: *const Scene, child: *const Node) f32 {
    if (std.mem.eql(u8, child.type, "text")) return scene.text.ascent(child.fontSize());
    return 0;
}

fn orderedIndices(n: *const Node, out: []usize, count: usize) void {
    for (0..count) |i| out[i] = i;
    var i: usize = 1;
    while (i < count) : (i += 1) {
        const cur = out[i];
        var j = i;
        while (j > 0 and n.children[out[j - 1]].style.order > n.children[cur].style.order) : (j -= 1) {
            out[j] = out[j - 1];
        }
        out[j] = cur;
    }
}

/// Resolve flexible lengths for one line, respecting min/max clamping.
fn distribute(infos: []ItemInfo, frozen: []bool, start: usize, end: usize, main_avail: f32, gap: f32, growing: bool) void {
    const nline = end - start;
    @memset(frozen[start..end], false);
    var iterations: usize = 0;
    while (iterations <= nline) : (iterations += 1) {
        var used: f32 = gap * @as(f32, @floatFromInt(if (nline > 1) nline - 1 else 0));
        for (start..end) |k| {
            const info = &infos[k];
            used += info.main_size + info.main_before + info.main_after;
        }
        const free = main_avail - used;
        if ((growing and free <= 0) or (!growing and free >= 0)) return;

        var total: f32 = 0;
        for (start..end) |k| {
            if (frozen[k]) continue;
            const info = &infos[k];
            total += if (growing) info.grow else info.shrink * info.base_main;
        }
        if (total <= 0) return;

        var clamped = false;
        for (start..end) |k| {
            if (frozen[k]) continue;
            const info = &infos[k];
            const factor = if (growing) info.grow else info.shrink * info.base_main;
            if (factor <= 0) continue;
            var target = info.main_size + free * factor / total;
            if (target < info.min_main) {
                target = info.min_main;
                if (!growing) {
                    frozen[k] = true;
                    clamped = true;
                }
            }
            if (target > info.max_main) {
                target = info.max_main;
                if (growing) {
                    frozen[k] = true;
                    clamped = true;
                }
            }
            infos[k].main_size = target;
        }
        if (!clamped) return;
    }
}

pub fn layout(self: *Scene, n: *const Node, bounds: Rect, inner_width: f32, inner_height: f32) std.mem.Allocator.Error!void {
    const is_row = isRowFlex(n);
    const reverse = std.mem.eql(u8, n.style.flexDirection, "row-reverse") or std.mem.eql(u8, n.style.flexDirection, "column-reverse");
    const wrap_reverse = std.mem.eql(u8, n.style.flexWrap, "wrap-reverse");
    const main_avail = if (is_row) inner_width else inner_height;
    const cross_avail = if (is_row) inner_height else inner_width;
    const wrap = (std.mem.eql(u8, n.style.flexWrap, "wrap") or wrap_reverse) and main_avail > 0;
    const gap = n.style.gap;
    const count = n.children.len;
    if (count == 0) return;

    const pad = n.padding();
    const bd = n.border();
    const mg = n.margin();

    // Scene-owned workspace scales with the actual children instead of silently
    // dropping siblings after a fixed stack buffer fills up.
    const allocator = self.arena.allocator();
    const order = try allocator.alloc(usize, count);
    orderedIndices(n, order, count);

    const infos = try allocator.alloc(ItemInfo, count);
    const frozen = try allocator.alloc(bool, count);
    const main_start = try allocator.alloc(f32, count);
    for (0..count) |k| {
        const child = &n.children[order[k]];
        var info = ItemInfo{ .child = child };
        const child_mg = child.marginRaw();
        info.mt = child_mg.top;
        info.mr = child_mg.right;
        info.mb = child_mg.bottom;
        info.ml = child_mg.left;

        const before = if (is_row) info.ml else info.mt;
        const after = if (is_row) info.mr else info.mb;
        const cross_before = if (is_row) info.mt else info.ml;
        const cross_after = if (is_row) info.mb else info.mr;

        info.main_before_auto = isAuto(before);
        info.main_after_auto = isAuto(after);
        info.cross_before_auto = isAuto(cross_before);
        info.cross_after_auto = isAuto(cross_after);
        info.main_before = fixed(before);
        info.main_after = fixed(after);
        info.cross_before = fixed(cross_before);
        info.cross_after = fixed(cross_after);

        info.grow = @max(0, child.style.flexGrow);
        info.shrink = @max(0, child.style.flexShrink);
        info.min_main = minMainSize(self, child, is_row);
        info.max_main = @max(info.min_main, maxMainSize(child, is_row));
        info.base_main = std.math.clamp(resolveMainBasis(self, child, is_row), info.min_main, info.max_main);
        info.main_size = info.base_main;
        info.cross_size = hypotheticalCross(self, child, is_row);
        infos[k] = info;
    }

    // Break the ordered items into flex lines.
    const line_start = try allocator.alloc(usize, count);
    const line_end = try allocator.alloc(usize, count);
    var line_count: usize = 0;
    {
        var start: usize = 0;
        var used: f32 = 0;
        for (0..count) |k| {
            const info = &infos[k];
            const outer = info.base_main + info.main_before + info.main_after;
            if (k == start) {
                used = outer;
            } else if (wrap and used + gap + outer > main_avail) {
                line_start[line_count] = start;
                line_end[line_count] = k;
                line_count += 1;
                start = k;
                used = outer;
            } else {
                used += gap + outer;
            }
        }
        line_start[line_count] = start;
        line_end[line_count] = count;
        line_count += 1;
    }

    // Hypothetical line cross sizes (including fixed cross margins).
    const line_cross = try allocator.alloc(f32, line_count);
    for (0..line_count) |li| {
        var c: f32 = 0;
        for (line_start[li]..line_end[li]) |k| {
            const info = &infos[k];
            const outer = info.cross_size + info.cross_before + info.cross_after;
            if (outer > c) c = outer;
        }
        line_cross[li] = c;
    }

    // align-content: stretch grows lines to fill the remaining cross space.
    if (std.mem.eql(u8, n.style.alignContent, "stretch") and cross_avail > 0) {
        var content_cross: f32 = gap * @as(f32, @floatFromInt(if (line_count > 1) line_count - 1 else 0));
        for (0..line_count) |li| content_cross += line_cross[li];
        const cross_free = cross_avail - content_cross;
        if (cross_free > 0) {
            if (line_count == 1) {
                line_cross[0] += cross_free;
            } else {
                const share = cross_free / @as(f32, @floatFromInt(line_count));
                for (0..line_count) |li| line_cross[li] += share;
            }
        }
    }

    // Stretch items with auto cross sizes inside their line.
    for (0..line_count) |li| {
        for (line_start[li]..line_end[li]) |k| {
            const info = &infos[k];
            if (info.cross_before_auto or info.cross_after_auto) continue;
            if (!std.mem.eql(u8, alignOf(n, info.child), "stretch")) continue;
            const definite = if (is_row) info.child.style.height > 0 else info.child.style.width > 0;
            if (definite) continue;
            const available = line_cross[li] - info.cross_before - info.cross_after;
            info.cross_size = clampCross(info.child, is_row, @max(0, available));
        }
    }

    // align-content: positions and gaps for each line on the cross axis.
    const cross_pos = try allocator.alloc(f32, line_count);
    {
        var total: f32 = gap * @as(f32, @floatFromInt(if (line_count > 1) line_count - 1 else 0));
        for (0..line_count) |li| total += line_cross[li];
        const free_cross = cross_avail - total;
        var cross_gap = gap;
        var cursor: f32 = 0;
        const ac = n.style.alignContent;
        if (std.mem.eql(u8, ac, "center")) {
            cursor = free_cross * 0.5;
        } else if (std.mem.eql(u8, ac, "flex-end") or std.mem.eql(u8, ac, "end")) {
            cursor = free_cross;
        } else if (std.mem.eql(u8, ac, "space-between") and line_count > 1 and free_cross > 0) {
            cross_gap = gap + free_cross / @as(f32, @floatFromInt(line_count - 1));
        } else if (std.mem.eql(u8, ac, "space-around") and line_count > 0 and free_cross > 0) {
            cursor = free_cross / @as(f32, @floatFromInt(line_count * 2));
            cross_gap = gap + free_cross / @as(f32, @floatFromInt(line_count));
        } else if (std.mem.eql(u8, ac, "space-evenly") and line_count > 0 and free_cross > 0) {
            cursor = free_cross / @as(f32, @floatFromInt(line_count + 1));
            cross_gap = gap + free_cross / @as(f32, @floatFromInt(line_count + 1));
        }
        if (cursor < 0) cursor = 0;
        for (0..line_count) |li| {
            cross_pos[li] = if (wrap_reverse and line_count > 1) cross_avail - cursor - line_cross[li] else cursor;
            cursor += line_cross[li] + cross_gap;
        }
    }

    // Container content origins, from the box model rings.
    const main_base = if (is_row) bounds.x + pad.left + bd.left + mg.left else bounds.y + pad.top + bd.top + mg.top;
    const cross_base = if (is_row) bounds.y + pad.top + bd.top + mg.top else bounds.x + pad.left + bd.left + mg.left;

    // Lay out each line.
    for (0..line_count) |li| {
        const start = line_start[li];
        const end = line_end[li];
        const nline = end - start;
        if (nline == 0) continue;

        for (start..end) |k| infos[k].main_size = infos[k].base_main;

        // Flex grow / shrink.
        var used: f32 = gap * @as(f32, @floatFromInt(if (nline > 1) nline - 1 else 0));
        var grow_total: f32 = 0;
        var shrink_total: f32 = 0;
        var main_auto_count: usize = 0;
        for (start..end) |k| {
            const info = &infos[k];
            used += info.base_main + info.main_before + info.main_after;
            grow_total += info.grow;
            shrink_total += info.shrink * info.base_main;
            main_auto_count += @as(usize, @intFromBool(info.main_before_auto)) + @as(usize, @intFromBool(info.main_after_auto));
        }
        const initial_free = main_avail - used;
        if (initial_free > 0 and grow_total > 0) {
            distribute(infos, frozen, start, end, main_avail, gap, true);
        } else if (initial_free < 0 and shrink_total > 0) {
            distribute(infos, frozen, start, end, main_avail, gap, false);
        }

        // Auto margins absorb positive free space after flexing.
        used = gap * @as(f32, @floatFromInt(if (nline > 1) nline - 1 else 0));
        for (start..end) |k| {
            const info = &infos[k];
            used += info.main_size + info.main_before + info.main_after;
        }
        var free = main_avail - used;
        var auto_each: f32 = 0;
        if (main_auto_count > 0) {
            if (free > 0) {
                auto_each = free / @as(f32, @floatFromInt(main_auto_count));
                free = 0;
            }
        }

        // justify-content applies only when no auto margins consumed the free space.
        var lead: f32 = 0;
        var extra_gap: f32 = 0;
        if (main_auto_count == 0 and free > 0) {
            const jc = n.style.justifyContent;
            if (std.mem.eql(u8, jc, "center")) {
                lead = free * 0.5;
            } else if (std.mem.eql(u8, jc, "flex-end") or std.mem.eql(u8, jc, "end")) {
                lead = free;
            } else if (std.mem.eql(u8, jc, "space-between") and nline > 1) {
                extra_gap = free / @as(f32, @floatFromInt(nline - 1));
            } else if (std.mem.eql(u8, jc, "space-around")) {
                lead = free / @as(f32, @floatFromInt(nline * 2));
                extra_gap = free / @as(f32, @floatFromInt(nline));
            } else if (std.mem.eql(u8, jc, "space-evenly")) {
                lead = free / @as(f32, @floatFromInt(nline + 1));
                extra_gap = free / @as(f32, @floatFromInt(nline + 1));
            }
        }

        // Main-axis positions, then mirror for *-reverse directions.
        {
            var cursor = lead;
            for (start..end) |k| {
                const info = &infos[k];
                const before = if (info.main_before_auto) auto_each else info.main_before;
                const after = if (info.main_after_auto) auto_each else info.main_after;
                cursor += before;
                main_start[k] = cursor;
                cursor += info.main_size + after + gap + extra_gap;
            }
        }
        if (reverse) {
            for (start..end) |k| {
                main_start[k] = main_avail - main_start[k] - infos[k].main_size;
            }
        }

        // Baseline reference for the line.
        var max_baseline: f32 = 0;
        if (is_row) {
            for (start..end) |k| {
                const info = &infos[k];
                if (std.mem.eql(u8, alignOf(n, info.child), "baseline")) {
                    const b = baselineOf(self, info.child);
                    if (b > max_baseline) max_baseline = b;
                }
            }
        }

        // Cross-axis alignment and placement.
        for (start..end) |k| {
            const info = &infos[k];
            const child = info.child;
            var offset: f32 = 0;
            const remaining = line_cross[li] - info.cross_size - info.cross_before - info.cross_after;
            if (info.cross_before_auto and info.cross_after_auto) {
                if (remaining > 0) offset = remaining * 0.5;
            } else if (info.cross_before_auto) {
                if (remaining > 0) offset = remaining;
            } else if (info.cross_after_auto) {
                offset = 0;
            } else {
                const al = alignOf(n, child);
                if (std.mem.eql(u8, al, "center")) {
                    if (remaining > 0) offset = remaining * 0.5;
                } else if (std.mem.eql(u8, al, "flex-end") or std.mem.eql(u8, al, "end")) {
                    if (remaining > 0) offset = remaining;
                } else if (std.mem.eql(u8, al, "baseline") and is_row) {
                    const b = baselineOf(self, child);
                    if (b < max_baseline) offset = max_baseline - b;
                }
            }

            const main_pos = main_base + main_start[k];
            const cross_pos_abs = cross_base + cross_pos[li] + info.cross_before + offset;
            const rect = if (is_row)
                Rect{ .x = main_pos, .y = cross_pos_abs, .width = info.main_size, .height = info.cross_size }
            else
                Rect{ .x = cross_pos_abs, .y = main_pos, .width = info.cross_size, .height = info.main_size };
            try self.layout(child, rect, n.id);
        }
    }
}
