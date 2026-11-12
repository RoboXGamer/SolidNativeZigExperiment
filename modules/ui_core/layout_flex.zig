//! CSS flexbox layout: iterative flexible length resolution (W3C CSS Flexbox §9.7 / Taffy),
//! typed flex-basis, cross-axis alignment, stretch, baseline remeasurement, and document order.
//!
const std = @import("std");
const root = @import("root.zig");
const Node = root.Node;
const Rect = root.Rect;
const Edges = root.Edges;
const Scene = root.Scene;
const sizing = root.sizing;

const ItemInfo = struct {
    child: *const Node,
    // Fixed margins
    mt: f32 = 0,
    mr: f32 = 0,
    mb: f32 = 0,
    ml: f32 = 0,

    // Margins along main and cross axes
    main_before: f32 = 0,
    main_after: f32 = 0,
    cross_before: f32 = 0,
    cross_after: f32 = 0,
    main_before_auto: bool = false,
    main_after_auto: bool = false,
    cross_before_auto: bool = false,
    cross_after_auto: bool = false,

    // Flex properties
    flex_basis: f32 = 0, // raw flex base size (border box)
    inner_flex_basis: f32 = 0, // content-box base size for shrink scaling
    hypothetical_main: f32 = 0, // clamped flex base size
    target_main: f32 = 0, // resolved main size (border box)
    cross_size: f32 = 0, // resolved cross size (border box)
    grow: f32 = 0,
    shrink: f32 = 1,
    min_main: f32 = 0,
    max_main: f32 = std.math.inf(f32),
    frozen: bool = false,
    violation: f32 = 0,
};

const ChildPlacement = struct {
    rect: Rect,
    used_margin: Edges,
};

fn isRowFlex(n: *const Node) bool {
    return std.mem.eql(u8, n.style.flexDirection, "row") or std.mem.eql(u8, n.style.flexDirection, "row-reverse");
}

fn frameWidth(n: *const Node) f32 {
    return n.padding().horizontal() + n.border().horizontal();
}

fn preferred(n: *const Node, horizontal: bool) ?f32 {
    const value = (if (horizontal) n.style.width else n.style.height) orelse return null;
    const frame = if (horizontal) frameWidth(n) else n.padding().vertical() + n.border().vertical();
    return n.constrain(n.borderSize(value, frame), horizontal);
}

/// Content height (border box, excludes the node's own margins).
fn contentHeight(scene: *const Scene, n: *const Node) f32 {
    if (preferred(n, false)) |height| return height;
    return scene.naturalHeight(n);
}

/// Max-content width (border box) measured with backend text metrics or recursive intrinsic sizing.
fn maxContentWidth(scene: *const Scene, n: *const Node) f32 {
    if (preferred(n, true)) |width| return width;
    if (std.mem.eql(u8, n.type, "text")) return scene.textFor(n).maxContentWidth(n.text, n.fontSize()) + frameWidth(n);
    if (!std.mem.eql(u8, n.style.display, "flex")) {
        return scene.intrinsicWidthFor(n, .max_content);
    }
    var inner: f32 = 0;
    const is_row = isRowFlex(n);
    const gap = n.mainGap(is_row);
    if (is_row) {
        var first = true;
        for (n.children) |*c| {
            if (c.isOutOfFlow()) continue;
            if (!first) inner += gap;
            inner += maxContentWidth(scene, c);
            first = false;
        }
    } else {
        for (n.children) |*c| {
            if (c.isOutOfFlow()) continue;
            const w = maxContentWidth(scene, c);
            if (w > inner) inner = w;
        }
    }
    return inner + frameWidth(n);
}

/// Min-content width (border box): widest unbreakable word or intrinsic minimum.
fn minContentWidth(scene: *const Scene, n: *const Node) f32 {
    if (preferred(n, true)) |width| return width;
    if (std.mem.eql(u8, n.type, "text")) return scene.textFor(n).minContentWidth(n.text, n.fontSize()) + frameWidth(n);
    if (!std.mem.eql(u8, n.style.display, "flex")) {
        return scene.intrinsicWidthFor(n, .min_content);
    }
    var inner: f32 = 0;
    const is_row = isRowFlex(n);
    const gap = n.mainGap(is_row);
    if (is_row) {
        var first = true;
        for (n.children) |*c| {
            if (c.isOutOfFlow()) continue;
            if (!first) inner += gap;
            inner += minContentWidth(scene, c);
            first = false;
        }
    } else {
        for (n.children) |*c| {
            if (c.isOutOfFlow()) continue;
            const w = minContentWidth(scene, c);
            if (w > inner) inner = w;
        }
    }
    return inner + frameWidth(n);
}

fn hypotheticalCross(scene: *const Scene, child: *const Node, is_row: bool) f32 {
    if (is_row) {
        return preferred(child, false) orelse contentHeight(scene, child);
    }
    return preferred(child, true) orelse maxContentWidth(scene, child);
}

fn clampCross(child: *const Node, is_row: bool, v: f32) f32 {
    return child.constrain(v, !is_row);
}

fn resolveMainBasis(scene: *const Scene, child: *const Node, is_row: bool, available_main: ?f32, available_cross: f32) f32 {
    const main_frame = if (is_row) frameWidth(child) else child.padding().vertical() + child.border().vertical();

    // 1. Definite numeric flexBasis
    if (child.style.flexBasis) |b| {
        return child.borderSize(b, main_frame);
    }

    // 2. CSS string flexBasis (keywords, percentages, lengths)
    if (child.style.flexBasisCss) |css| {
        const trimmed = std.mem.trim(u8, css, " \t\r\n");
        if (std.mem.eql(u8, trimmed, "content") or child.style.flexBasisContent) {
            return if (is_row) maxContentWidth(scene, child) else scene.naturalHeightForWidth(child, available_cross);
        } else if (std.mem.eql(u8, trimmed, "max-content")) {
            return if (is_row) scene.intrinsicWidthFor(child, .max_content) else contentHeight(scene, child);
        } else if (std.mem.eql(u8, trimmed, "min-content")) {
            return if (is_row) scene.intrinsicWidthFor(child, .min_content) else minMainSize(scene, child, is_row);
        } else if (std.mem.eql(u8, trimmed, "fit-content")) {
            if (is_row and available_main != null) {
                return scene.intrinsicWidthFor(child, .{ .definite = available_main.? });
            } else {
                return if (is_row) scene.intrinsicWidthFor(child, .max_content) else contentHeight(scene, child);
            }
        } else if (!std.mem.eql(u8, trimmed, "auto")) {
            var ctx = scene.length_context;
            ctx.font_size = child.fontSize();
            ctx.percentage = available_main;
            if (sizing.resolve(trimmed, ctx)) |res| {
                switch (res) {
                    .length => |val| return child.borderSize(val, main_frame),
                    .keyword => |kw| switch (kw) {
                        .max_content => return if (is_row) scene.intrinsicWidthFor(child, .max_content) else contentHeight(scene, child),
                        .min_content => return if (is_row) scene.intrinsicWidthFor(child, .min_content) else minMainSize(scene, child, is_row),
                        .fit_content => return if (is_row and available_main != null) scene.intrinsicWidthFor(child, .{ .definite = available_main.? }) else if (is_row) scene.intrinsicWidthFor(child, .max_content) else contentHeight(scene, child),
                        .auto, .none => {},
                    },
                    .unresolved => {},
                }
            } else |_| {}
        }
    }

    if (child.style.flexBasisContent) {
        return if (is_row) maxContentWidth(scene, child) else scene.naturalHeightForWidth(child, available_cross);
    }

    // 3. flex-basis: auto -> looks at main size property (width or height), else aspect-ratio, else content
    if (preferred(child, is_row)) |value| return value;

    if (preferred(child, !is_row)) |cross| {
        if (child.aspectRatio()) |ratio| {
            const cross_frame = if (is_row) child.padding().vertical() + child.border().vertical() else frameWidth(child);
            const basis = if (std.mem.eql(u8, child.style.boxSizing, "content-box")) @max(0, cross - cross_frame) else cross;
            return child.borderSize(if (is_row) basis * ratio else basis / ratio, main_frame);
        }
    }

    if (is_row) {
        return maxContentWidth(scene, child);
    }
    return scene.naturalHeightForWidth(child, available_cross);
}

fn minMainSize(scene: *const Scene, child: *const Node, is_row: bool) f32 {
    const frame = if (is_row) frameWidth(child) else child.padding().vertical() + child.border().vertical();
    if (is_row) {
        if (child.style.minWidth) |value| return child.borderSize(value, frame);
        // Automatic minimum size (CSS Flexbox §4.5):
        // If overflow is not visible, auto min-size is 0.
        if (!std.mem.eql(u8, child.style.overflow, "visible")) {
            return frame;
        }
        var content = child.*;
        content.style.width = null;
        const intrinsic = minContentWidth(scene, &content);
        return if (preferred(child, true)) |width| @min(width, intrinsic) else intrinsic;
    } else {
        if (child.style.minHeight) |value| return child.borderSize(value, frame);
        if (!std.mem.eql(u8, child.style.overflow, "visible")) {
            return frame;
        }
        return if (preferred(child, false)) |height| height else contentHeight(scene, child);
    }
}

fn maxMainSize(child: *const Node, is_row: bool) f32 {
    const max = (if (is_row) child.style.maxWidth else child.style.maxHeight) orelse return std.math.inf(f32);
    return child.borderSize(max, if (is_row) frameWidth(child) else child.padding().vertical() + child.border().vertical());
}

fn alignOf(container: *const Node, child: *const Node) []const u8 {
    if (std.mem.eql(u8, child.style.alignSelf, "auto")) return container.style.alignItems;
    return child.style.alignSelf;
}

pub fn findFirstBaseline(scene: *const Scene, n: *const Node) ?f32 {
    const pad_top = n.padding().top;
    const bd_top = n.border().top;
    if (std.mem.eql(u8, n.type, "text")) {
        return pad_top + bd_top + scene.textFor(n).ascent(n.fontSize());
    }
    for (n.children) |*child| {
        if (findFirstBaseline(scene, child)) |b| {
            return pad_top + bd_top + child.margin().top + b;
        }
    }
    return null;
}

pub fn findLastBaseline(scene: *const Scene, n: *const Node) ?f32 {
    const pad_top = n.padding().top;
    const bd_top = n.border().top;
    if (std.mem.eql(u8, n.type, "text")) {
        const line_h = if (n.style.lineHeight) |lh| (if (lh > 0) lh else scene.textFor(n).lineHeight(n.fontSize())) else scene.textFor(n).lineHeight(n.fontSize());
        var lines: usize = 1;
        for (n.text) |ch| if (ch == '\n') {
            lines += 1;
        };
        return pad_top + bd_top + @as(f32, @floatFromInt(lines - 1)) * line_h + scene.textFor(n).ascent(n.fontSize());
    }
    var i = n.children.len;
    while (i > 0) {
        i -= 1;
        if (findLastBaseline(scene, &n.children[i])) |b| {
            return pad_top + bd_top + n.children[i].margin().top + b;
        }
    }
    return null;
}

/// First baseline offset from top of box.
pub fn firstBaselineOf(scene: *const Scene, child: *const Node) f32 {
    if (std.mem.eql(u8, child.type, "text")) return scene.textFor(child).ascent(child.fontSize());
    if (findFirstBaseline(scene, child)) |b| return b;
    return child.constrain(scene.naturalHeight(child), false);
}

/// Last baseline offset from top of box.
pub fn lastBaselineOf(scene: *const Scene, child: *const Node) f32 {
    if (findLastBaseline(scene, child)) |b| return b;
    return child.constrain(scene.naturalHeight(child), false);
}

/// Default baseline offset (first baseline).
pub fn baselineOf(scene: *const Scene, child: *const Node) f32 {
    return firstBaselineOf(scene, child);
}

fn orderedInFlowIndices(n: *const Node, out: []usize) void {
    var idx: usize = 0;
    for (n.children, 0..) |*child, i| {
        if (!child.isOutOfFlow()) {
            out[idx] = i;
            idx += 1;
        }
    }
    const count = out.len;
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

/// W3C CSS Flexbox §9.7 / Taffy iterative flexible length resolution algorithm.
fn resolveFlexibleLengths(infos: []ItemInfo, start: usize, end: usize, main_avail: f32, gap: f32) void {
    const nline = end - start;
    if (nline == 0) return;
    const total_gap = gap * @as(f32, @floatFromInt(if (nline > 1) nline - 1 else 0));

    // 1. Determine used flex factor
    var total_hypothetical: f32 = total_gap;
    for (start..end) |k| {
        total_hypothetical += infos[k].hypothetical_main + infos[k].main_before + infos[k].main_after;
    }
    const growing = total_hypothetical < main_avail;
    const shrinking = total_hypothetical > main_avail;
    const exactly_sized = !growing and !shrinking;

    // 2. Size inflexible items
    for (start..end) |k| {
        const item = &infos[k];
        item.target_main = item.hypothetical_main;
        if (exactly_sized or
            (item.grow == 0 and item.shrink == 0) or
            (growing and (item.grow == 0 or item.flex_basis > item.hypothetical_main)) or
            (shrinking and (item.shrink == 0 or item.flex_basis < item.hypothetical_main)))
        {
            item.frozen = true;
        } else {
            item.frozen = false;
        }
    }

    if (exactly_sized) return;

    // 3. Calculate initial free space
    var used_space: f32 = total_gap;
    for (start..end) |k| {
        const item = &infos[k];
        const base_size = if (item.frozen) item.target_main else item.flex_basis;
        used_space += base_size + item.main_before + item.main_after;
    }
    const initial_free_space = main_avail - used_space;

    // 4. Iterative loop
    var iteration: usize = 0;
    while (iteration <= nline) : (iteration += 1) {
        // a. Check for flexible items
        var all_frozen = true;
        var items_space: f32 = 0;
        var sum_flex_grow: f32 = 0;
        var sum_flex_shrink: f32 = 0;
        for (start..end) |k| {
            const item = &infos[k];
            if (item.frozen) {
                items_space += item.target_main + item.main_before + item.main_after;
            } else {
                all_frozen = false;
                items_space += item.flex_basis + item.main_before + item.main_after;
                sum_flex_grow += item.grow;
                sum_flex_shrink += item.shrink;
            }
        }
        if (all_frozen) break;

        // b. Calculate remaining free space
        const current_used = total_gap + items_space;
        const remaining_free_space = main_avail - current_used;
        var free_space: f32 = remaining_free_space;

        if (growing and sum_flex_grow < 1.0) {
            const fractional_free = initial_free_space * sum_flex_grow;
            free_space = @min(fractional_free, remaining_free_space);
        } else if (shrinking and sum_flex_shrink < 1.0) {
            const fractional_free = initial_free_space * sum_flex_shrink;
            free_space = @max(fractional_free, remaining_free_space);
        }

        // c. Distribute free space proportional to flex factors
        if (growing and sum_flex_grow > 0) {
            for (start..end) |k| {
                const item = &infos[k];
                if (!item.frozen) {
                    item.target_main = item.flex_basis + free_space * (item.grow / sum_flex_grow);
                }
            }
        } else if (shrinking and sum_flex_shrink > 0) {
            var sum_scaled_shrink: f32 = 0;
            for (start..end) |k| {
                const item = &infos[k];
                if (!item.frozen) {
                    sum_scaled_shrink += item.inner_flex_basis * item.shrink;
                }
            }
            if (sum_scaled_shrink > 0) {
                for (start..end) |k| {
                    const item = &infos[k];
                    if (!item.frozen) {
                        const scaled = item.inner_flex_basis * item.shrink;
                        item.target_main = item.flex_basis + free_space * (scaled / sum_scaled_shrink);
                    }
                }
            }
        }

        // d. Fix min/max violations
        var total_violation: f32 = 0;
        for (start..end) |k| {
            const item = &infos[k];
            if (!item.frozen) {
                const clamped = std.math.clamp(item.target_main, item.min_main, item.max_main);
                item.violation = clamped - item.target_main;
                item.target_main = clamped;
                total_violation += item.violation;
            }
        }

        // e. Freeze over-flexed items
        for (start..end) |k| {
            const item = &infos[k];
            if (!item.frozen) {
                if (total_violation > 0) {
                    if (item.violation > 0) item.frozen = true;
                } else if (total_violation < 0) {
                    if (item.violation < 0) item.frozen = true;
                } else {
                    item.frozen = true;
                }
            }
        }
    }
}

pub fn layout(self: *Scene, n: *const Node, bounds: Rect, inner_width: f32, inner_height: f32) anyerror!void {
    const is_row = isRowFlex(n);
    const rtl = std.mem.eql(u8, n.style.direction, "rtl");
    const reversed = std.mem.eql(u8, n.style.flexDirection, "row-reverse") or std.mem.eql(u8, n.style.flexDirection, "column-reverse");
    const reverse = reversed != (is_row and rtl);
    const wrap_reverse = std.mem.eql(u8, n.style.flexWrap, "wrap-reverse") != (!is_row and rtl);
    const main_avail = if (is_row) inner_width else inner_height;
    const cross_avail = if (is_row) inner_height else inner_width;
    const wrap = (std.mem.eql(u8, n.style.flexWrap, "wrap") or wrap_reverse) and main_avail > 0;
    const main_gap = n.mainGap(is_row);
    const cross_gap = n.crossGap(is_row);
    const count = n.children.len;
    if (count == 0) return;

    var in_flow_count: usize = 0;
    for (n.children) |*child| {
        if (!child.isOutOfFlow()) in_flow_count += 1;
    }
    if (in_flow_count == 0) return;

    const pad = n.padding();
    const bd = n.border();

    const allocator = self.arena.allocator();
    const order = try allocator.alloc(usize, in_flow_count);
    orderedInFlowIndices(n, order);

    const infos = try allocator.alloc(ItemInfo, in_flow_count);
    const main_start = try allocator.alloc(f32, in_flow_count);

    for (0..in_flow_count) |k| {
        const child = &n.children[order[k]];
        var info = ItemInfo{ .child = child };
        const child_mg = child.margin();
        info.mt = child_mg.top;
        info.mr = child_mg.right;
        info.mb = child_mg.bottom;
        info.ml = child_mg.left;

        const before = if (is_row) (if (reverse) info.mr else info.ml) else (if (reverse) info.mb else info.mt);
        const after = if (is_row) (if (reverse) info.ml else info.mr) else (if (reverse) info.mt else info.mb);
        const cross_before = if (is_row) info.mt else info.ml;
        const cross_after = if (is_row) info.mb else info.mr;

        info.main_before_auto = if (is_row) (if (reverse) child.style.marginRightAuto else child.style.marginLeftAuto) else (if (reverse) child.style.marginBottomAuto else child.style.marginTopAuto);
        info.main_after_auto = if (is_row) (if (reverse) child.style.marginLeftAuto else child.style.marginRightAuto) else (if (reverse) child.style.marginTopAuto else child.style.marginBottomAuto);
        info.cross_before_auto = if (is_row) child.style.marginTopAuto else child.style.marginLeftAuto;
        info.cross_after_auto = if (is_row) child.style.marginBottomAuto else child.style.marginRightAuto;
        info.main_before = before;
        info.main_after = after;
        info.cross_before = cross_before;
        info.cross_after = cross_after;

        info.grow = @max(0, child.style.flexGrow);
        info.shrink = @max(0, child.style.flexShrink);
        info.min_main = minMainSize(self, child, is_row);
        info.max_main = @max(info.min_main, maxMainSize(child, is_row));

        const main_frame = if (is_row) frameWidth(child) else child.padding().vertical() + child.border().vertical();
        const available_width = if (is_row) main_avail else @max(0, cross_avail - info.cross_before - info.cross_after);
        info.flex_basis = resolveMainBasis(self, child, is_row, if (is_row) main_avail else null, available_width);
        info.inner_flex_basis = @max(0, info.flex_basis - main_frame);
        info.hypothetical_main = std.math.clamp(info.flex_basis, info.min_main, info.max_main);
        info.target_main = info.hypothetical_main;
        info.cross_size = hypotheticalCross(self, child, is_row);
        infos[k] = info;
    }

    // Break the ordered items into flex lines.
    const line_start = try allocator.alloc(usize, in_flow_count);
    const line_end = try allocator.alloc(usize, in_flow_count);
    var line_count: usize = 0;
    {
        var start: usize = 0;
        var used: f32 = 0;
        for (0..in_flow_count) |k| {
            const info = &infos[k];
            const outer = info.hypothetical_main + info.main_before + info.main_after;
            if (k == start) {
                used = outer;
            } else if (wrap and used + main_gap + outer > main_avail) {
                line_start[line_count] = start;
                line_end[line_count] = k;
                line_count += 1;
                start = k;
                used = outer;
            } else {
                used += main_gap + outer;
            }
        }
        line_start[line_count] = start;
        line_end[line_count] = in_flow_count;
        line_count += 1;
    }

    // Resolve flexible main lengths for each line.
    for (0..line_count) |li| {
        resolveFlexibleLengths(infos, line_start[li], line_end[li], main_avail, main_gap);
    }

    // Remeasure cross sizes of items whose cross size is auto, now that target main size is known.
    for (0..line_count) |li| {
        for (line_start[li]..line_end[li]) |k| {
            const info = &infos[k];
            const child = info.child;
            const cross_auto = if (is_row) child.style.height == null else child.style.width == null;
            if (is_row and cross_auto) {
                info.cross_size = self.naturalHeightForWidth(child, info.target_main);
            } else if (!is_row and cross_auto) {
                if (child.aspectRatio()) |ratio| {
                    const frame_w = child.padding().horizontal() + child.border().horizontal();
                    const frame_h = child.padding().vertical() + child.border().vertical();
                    const content_sizing = std.mem.eql(u8, child.style.boxSizing, "content-box");
                    const basis = if (content_sizing) @max(0, info.target_main - frame_h) else info.target_main;
                    info.cross_size = child.constrain(child.borderSize(basis * ratio, frame_w), true);
                }
            }
            if (cross_auto) if (child.aspectRatio()) |ratio| {
                const frame_w = child.padding().horizontal() + child.border().horizontal();
                const frame_h = child.padding().vertical() + child.border().vertical();
                const content_sizing = std.mem.eql(u8, child.style.boxSizing, "content-box");
                if (is_row) {
                    const basis = if (content_sizing) @max(0, info.target_main - frame_w) else info.target_main;
                    info.cross_size = child.constrain(child.borderSize(basis / ratio, frame_h), false);
                } else {
                    const basis = if (content_sizing) @max(0, info.target_main - frame_h) else info.target_main;
                    info.cross_size = child.constrain(child.borderSize(basis * ratio, frame_w), true);
                }
            };
        }
    }

    // Line cross sizes (including fixed cross margins).
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

    // Single-line containers with definite cross size fill the cross size independently
    // of align-content (W3C Flexbox §9.4 / FLEX-04). Multi-line containers use align-content: stretch.
    if (line_count == 1 and !wrap and cross_avail > 0) {
        line_cross[0] = cross_avail;
    } else if (std.mem.eql(u8, n.style.alignContent, "stretch") and cross_avail > 0) {
        var content_cross: f32 = cross_gap * @as(f32, @floatFromInt(if (line_count > 1) line_count - 1 else 0));
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
            if (info.child.aspectRatio() != null) continue;
            const definite = if (is_row) info.child.style.height != null else info.child.style.width != null;
            if (definite) continue;
            const available = line_cross[li] - info.cross_before - info.cross_after;
            info.cross_size = clampCross(info.child, is_row, @max(0, available));
        }
    }

    // align-content: positions and gaps for each line on the cross axis.
    const cross_pos = try allocator.alloc(f32, line_count);
    {
        var total: f32 = cross_gap * @as(f32, @floatFromInt(if (line_count > 1) line_count - 1 else 0));
        for (0..line_count) |li| total += line_cross[li];
        const free_cross = cross_avail - total;
        var actual_cross_gap = cross_gap;
        var cursor: f32 = 0;
        var ac = n.style.alignContent;
        const safe_ac = std.mem.startsWith(u8, ac, "safe ");
        if (safe_ac) ac = ac[5..] else if (std.mem.startsWith(u8, ac, "unsafe ")) ac = ac[7..];
        if (std.mem.eql(u8, ac, "center")) {
            cursor = free_cross * 0.5;
        } else if (std.mem.eql(u8, ac, "flex-end") or std.mem.eql(u8, ac, "end")) {
            cursor = free_cross;
        } else if (std.mem.eql(u8, ac, "space-between") and line_count > 1 and free_cross > 0) {
            actual_cross_gap = cross_gap + free_cross / @as(f32, @floatFromInt(line_count - 1));
        } else if (std.mem.eql(u8, ac, "space-around") and line_count > 0 and free_cross > 0) {
            cursor = free_cross / @as(f32, @floatFromInt(line_count * 2));
            actual_cross_gap = cross_gap + free_cross / @as(f32, @floatFromInt(line_count));
        } else if (std.mem.eql(u8, ac, "space-evenly") and line_count > 0 and free_cross > 0) {
            cursor = free_cross / @as(f32, @floatFromInt(line_count + 1));
            actual_cross_gap = cross_gap + free_cross / @as(f32, @floatFromInt(line_count + 1));
        }
        if (safe_ac and cursor < 0) cursor = 0;
        for (0..line_count) |li| {
            cross_pos[li] = if (wrap_reverse) cross_avail - cursor - line_cross[li] else cursor;
            cursor += line_cross[li] + actual_cross_gap;
        }
    }

    // Container content origins, from the box model rings.
    const main_base = if (is_row) bounds.x + pad.left + bd.left else bounds.y + pad.top + bd.top;
    const cross_base = if (is_row) bounds.y + pad.top + bd.top else bounds.x + pad.left + bd.left;

    // Placements allocated indexed by original child index to preserve document order (FLEX-06).
    const placements = try allocator.alloc(ChildPlacement, count);

    // Lay out each line.
    for (0..line_count) |li| {
        const start = line_start[li];
        const end = line_end[li];
        const nline = end - start;
        if (nline == 0) continue;

        var used: f32 = main_gap * @as(f32, @floatFromInt(if (nline > 1) nline - 1 else 0));
        var main_auto_count: usize = 0;
        for (start..end) |k| {
            const info = &infos[k];
            used += info.target_main + info.main_before + info.main_after;
            main_auto_count += @as(usize, @intFromBool(info.main_before_auto)) + @as(usize, @intFromBool(info.main_after_auto));
        }

        // Auto margins absorb positive free space after flexing.
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
        if (main_auto_count == 0) {
            var jc = n.style.justifyContent;
            var is_safe = false;
            if (std.mem.startsWith(u8, jc, "safe ")) {
                is_safe = true;
                jc = jc[5..];
            } else if (std.mem.startsWith(u8, jc, "unsafe ")) {
                jc = jc[7..];
            }
            if (is_row) {
                if (std.mem.eql(u8, jc, "right")) jc = if (reverse) "flex-start" else "flex-end" else if (std.mem.eql(u8, jc, "left")) jc = if (reverse) "flex-end" else "flex-start" else if (std.mem.eql(u8, jc, "start")) jc = if (reverse == rtl) "flex-start" else "flex-end" else if (std.mem.eql(u8, jc, "end")) jc = if (reverse == rtl) "flex-end" else "flex-start";
            }
            if (is_safe and free < 0) {
                lead = 0;
            } else {
                if (std.mem.eql(u8, jc, "center")) {
                    lead = free * 0.5;
                } else if (std.mem.eql(u8, jc, "flex-end") or std.mem.eql(u8, jc, "end") or (is_row and std.mem.eql(u8, jc, "right"))) {
                    lead = free;
                } else if (std.mem.eql(u8, jc, "flex-start") or std.mem.eql(u8, jc, "start") or (is_row and std.mem.eql(u8, jc, "left"))) {
                    lead = 0;
                } else if (free > 0) {
                    if (std.mem.eql(u8, jc, "space-between") and nline > 1) {
                        extra_gap = free / @as(f32, @floatFromInt(nline - 1));
                    } else if (std.mem.eql(u8, jc, "space-around")) {
                        lead = free / @as(f32, @floatFromInt(nline * 2));
                        extra_gap = free / @as(f32, @floatFromInt(nline));
                    } else if (std.mem.eql(u8, jc, "space-evenly")) {
                        lead = free / @as(f32, @floatFromInt(nline + 1));
                        extra_gap = free / @as(f32, @floatFromInt(nline + 1));
                    }
                }
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
                cursor += info.target_main + after + main_gap + extra_gap;
            }
        }
        if (reverse) {
            for (start..end) |k| {
                main_start[k] = main_avail - main_start[k] - infos[k].target_main;
            }
        }

        // Baseline reference for the line.
        var max_baseline: f32 = 0;
        var max_last_baseline: f32 = 0;
        if (is_row) {
            for (start..end) |k| {
                const info = &infos[k];
                const al = alignOf(n, info.child);
                if (std.mem.eql(u8, al, "baseline") or std.mem.eql(u8, al, "first-baseline")) {
                    const b = baselineOf(self, info.child);
                    if (b > max_baseline) max_baseline = b;
                } else if (std.mem.eql(u8, al, "last-baseline")) {
                    const b = lastBaselineOf(self, info.child);
                    if (b > max_last_baseline) max_last_baseline = b;
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
                var al = alignOf(n, child);
                var is_safe = false;
                if (std.mem.startsWith(u8, al, "safe ")) {
                    is_safe = true;
                    al = al[5..];
                } else if (std.mem.startsWith(u8, al, "unsafe ")) {
                    al = al[7..];
                }
                if (is_safe and remaining < 0) {
                    offset = 0;
                } else if (std.mem.eql(u8, al, "center")) {
                    offset = remaining * 0.5;
                } else if (std.mem.eql(u8, al, "flex-end") or std.mem.eql(u8, al, "end")) {
                    offset = if (wrap_reverse) 0 else remaining;
                } else if (std.mem.eql(u8, al, "flex-start") or std.mem.eql(u8, al, "start")) {
                    offset = if (wrap_reverse) remaining else 0;
                } else if ((std.mem.eql(u8, al, "baseline") or std.mem.eql(u8, al, "first-baseline")) and is_row) {
                    const b = baselineOf(self, child);
                    if (b < max_baseline) offset = max_baseline - b;
                } else if (std.mem.eql(u8, al, "last-baseline") and is_row) {
                    const b = lastBaselineOf(self, child);
                    if (b < max_last_baseline) offset = max_last_baseline - b;
                }
            }

            const main_pos = main_base + main_start[k];
            const cross_pos_abs = cross_base + cross_pos[li] + info.cross_before + offset;
            const rect = if (is_row)
                Rect{ .x = main_pos, .y = cross_pos_abs, .width = info.target_main, .height = info.cross_size }
            else
                Rect{ .x = cross_pos_abs, .y = main_pos, .width = info.cross_size, .height = info.target_main };

            var margin = child.margin();
            const before = if (info.main_before_auto) auto_each else info.main_before;
            const after = if (info.main_after_auto) auto_each else info.main_after;
            const cross_before_used = if (info.cross_before_auto) offset else info.cross_before;
            const cross_after_used = if (info.cross_after_auto) @max(0, remaining - offset) else info.cross_after;
            if (is_row) {
                margin.left = if (reverse) after else before;
                margin.right = if (reverse) before else after;
                margin.top = cross_before_used;
                margin.bottom = cross_after_used;
            } else {
                margin.top = if (reverse) after else before;
                margin.bottom = if (reverse) before else after;
                margin.left = cross_before_used;
                margin.right = cross_after_used;
            }

            const orig_idx = order[k];
            placements[orig_idx] = .{
                .rect = rect,
                .used_margin = margin,
            };
        }
    }

    // Emit children in document order to preserve tab/focus order (FLEX-06).
    for (n.children, 0..) |*child, i| {
        if (child.isOutOfFlow()) continue;
        try self.layout(child, placements[i].rect, n.id);
        self.setUsedMargin(child.id, placements[i].used_margin);
    }
}
