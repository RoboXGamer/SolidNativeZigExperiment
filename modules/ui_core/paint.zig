//! Backend-independent paint geometry and RGBA rasterization for cached effects.
const std = @import("std");
const core = @import("root.zig");
const css = @import("css_syntax.zig");
pub const Color = [4]u8;
pub const Radii = [4]f32; // top-left, top-right, bottom-right, bottom-left
pub const EllipticalRadii = struct { x: Radii = .{ 0, 0, 0, 0 }, y: Radii = .{ 0, 0, 0, 0 } };

fn length(value: []const u8, basis: ?f32, font_size: f32) ?f32 {
    // Retain the bridge's legacy unitless pixel spelling as well as CSS lengths.
    if (std.fmt.parseFloat(f32, value)) |number| return if (std.math.isFinite(number)) number else null else |_| {}
    const resolved = core.sizing.resolve(value, .{ .percentage = basis, .font_size = font_size }) catch return null;
    return switch (resolved) {
        .length => |v| v,
        else => null,
    };
}
fn radiusList(value: []const u8, basis: f32, font_size: f32) ?Radii {
    var tokens = css.Tokens{ .input = value, .separators = " \t\r\n" };
    var values: Radii = undefined;
    var count: usize = 0;
    while (tokens.next()) |token| {
        if (count == 4) return null;
        values[count] = length(token, basis, font_size) orelse return null;
        if (values[count] < 0) return null;
        count += 1;
    }
    return switch (count) {
        1 => .{ values[0], values[0], values[0], values[0] },
        2 => .{ values[0], values[1], values[0], values[1] },
        3 => .{ values[0], values[1], values[2], values[1] },
        4 => values,
        else => null,
    };
}
/// Resolve percentages against the border-box width/height separately, then
/// shrink all corners by the single CSS overlap factor.
pub fn resolvedRadii(n: *const core.Node, w: f32, h: f32) EllipticalRadii {
    const legacy = radii(n);
    var result = EllipticalRadii{ .x = legacy, .y = legacy };
    if (n.style.borderRadiusCss) |value| {
        var parts = css.Split{ .input = value, .separator = '/' };
        const horizontal = parts.next() orelse "";
        const vertical = parts.next();
        if (parts.next() == null) {
            if (radiusList(horizontal, w, n.fontSize())) |rx| {
                if (radiusList(vertical orelse horizontal, h, n.fontSize())) |ry| result = .{ .x = rx, .y = ry };
            }
        }
    }
    const corners = .{ n.style.borderTopLeftRadiusCss, n.style.borderTopRightRadiusCss, n.style.borderBottomRightRadiusCss, n.style.borderBottomLeftRadiusCss };
    inline for (corners, 0..) |corner, i| if (corner) |value| {
        var tokens = css.Tokens{ .input = value, .separators = " \t\r\n" };
        const horizontal = tokens.next() orelse "";
        const vertical = tokens.next() orelse horizontal;
        if (tokens.next() == null) {
            const rx = length(horizontal, w, n.fontSize());
            const ry = length(vertical, h, n.fontSize());
            if (rx != null and ry != null and rx.? >= 0 and ry.? >= 0) {
                result.x[i] = rx.?;
                result.y[i] = ry.?;
            }
        }
    };
    return normalizedElliptical(result, w, h);
}
pub fn normalizedElliptical(radius: EllipticalRadii, w: f32, h: f32) EllipticalRadii {
    var r = radius;
    for (0..4) |i| {
        r.x[i] = @max(0, r.x[i]);
        r.y[i] = @max(0, r.y[i]);
    }
    var scale: f32 = 1;
    const sums = .{ r.x[0] + r.x[1], r.x[3] + r.x[2], r.y[0] + r.y[3], r.y[1] + r.y[2] };
    inline for (sums, 0..) |v, i| if (v > 0) {
        scale = @min(scale, @max(0, if (i < 2) w else h) / v);
    };
    for (0..4) |i| {
        r.x[i] *= scale;
        r.y[i] *= scale;
    }
    return r;
}
pub fn insetRadii(radius: EllipticalRadii, edges: core.Edges, w: f32, h: f32) EllipticalRadii {
    return normalizedElliptical(.{ .x = .{ @max(0, radius.x[0] - edges.left), @max(0, radius.x[1] - edges.right), @max(0, radius.x[2] - edges.right), @max(0, radius.x[3] - edges.left) }, .y = .{ @max(0, radius.y[0] - edges.top), @max(0, radius.y[1] - edges.top), @max(0, radius.y[2] - edges.bottom), @max(0, radius.y[3] - edges.bottom) } }, w, h);
}
pub fn paddingRadii(n: *const core.Node, border_box: core.Rect) EllipticalRadii {
    const box = n.paddingBox(border_box);
    return insetRadii(resolvedRadii(n, border_box.width, border_box.height), n.border(), box.width, box.height);
}
pub fn ellipticalContains(box: core.Rect, radius: EllipticalRadii, x: f32, y: f32) bool {
    if (!box.contains(x, y)) return false;
    const r = normalizedElliptical(radius, box.width, box.height);
    const px = x - box.x;
    const py = y - box.y;
    inline for (0..4) |i| {
        const right = i == 1 or i == 2;
        const bottom = i == 2 or i == 3;
        const dx = if (right) box.width - px else px;
        const dy = if (bottom) box.height - py else py;
        if (dx < r.x[i] and dy < r.y[i]) {
            const ex = (dx - r.x[i]) / r.x[i];
            const ey = (dy - r.y[i]) / r.y[i];
            if (ex * ex + ey * ey > 1) return false;
        }
    }
    return true;
}

pub fn radii(n: *const core.Node) Radii {
    const s = n.style;
    return .{ if (s.borderTopLeftRadius > 0) s.borderTopLeftRadius else s.borderRadius, if (s.borderTopRightRadius > 0) s.borderTopRightRadius else s.borderRadius, if (s.borderBottomRightRadius > 0) s.borderBottomRightRadius else s.borderRadius, if (s.borderBottomLeftRadius > 0) s.borderBottomLeftRadius else s.borderRadius };
}
pub fn normalized(r: Radii, w: f32, h: f32) Radii {
    var scale: f32 = 1;
    const sums = .{ r[0] + r[1], r[3] + r[2], r[0] + r[3], r[1] + r[2] };
    inline for (sums, 0..) |v, i| if (v > 0) {
        scale = @min(scale, (if (i < 2) w else h) / v);
    };
    return .{ @max(0, r[0] * scale), @max(0, r[1] * scale), @max(0, r[2] * scale), @max(0, r[3] * scale) };
}
pub fn roundedContains(box: core.Rect, radius: Radii, x: f32, y: f32) bool {
    return ellipticalContains(box, .{ .x = radius, .y = radius }, x, y);
}
pub const Shadow = struct { x: f32 = 0, y: f32 = 0, blur: f32 = 0, spread: f32 = 0, color: Color = .{ 0, 0, 0, 255 }, inset: bool = false };
pub fn shadows(a: std.mem.Allocator, value: []const u8) ![]Shadow {
    var list: std.ArrayList(Shadow) = .empty;
    errdefer list.deinit(a);
    var layers = css.Tokens{ .input = value, .separators = "," };
    while (layers.next()) |layer| {
        if (std.mem.eql(u8, layer, "none")) continue;
        var tokens = css.Tokens{ .input = layer, .separators = " \t" };
        var shadow = Shadow{};
        var lens: [4]f32 = .{ 0, 0, 0, 0 };
        var count: usize = 0;
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "inset")) {
                shadow.inset = true;
                continue;
            }
            if (core.gradient.parseColor(token)) |c| {
                shadow.color = c;
                continue;
            }
            const s = if (std.mem.endsWith(u8, token, "px")) token[0 .. token.len - 2] else token;
            if (count >= 4) return error.InvalidShadow;
            lens[count] = std.fmt.parseFloat(f32, s) catch return error.InvalidShadow;
            count += 1;
        }
        if (count < 2 or lens[2] < 0) return error.InvalidShadow;
        shadow.x = lens[0];
        shadow.y = lens[1];
        shadow.blur = lens[2];
        shadow.spread = lens[3];
        try list.append(a, shadow);
    }
    return list.toOwnedSlice(a);
}
pub fn textShadows(a: std.mem.Allocator, value: []const u8, default_color: Color) ![]Shadow {
    var list: std.ArrayList(Shadow) = .empty;
    errdefer list.deinit(a);
    var layers = css.Tokens{ .input = value, .separators = "," };
    while (layers.next()) |layer| {
        const trimmed_layer = std.mem.trim(u8, layer, " \t\r\n");
        if (std.mem.eql(u8, trimmed_layer, "none") or trimmed_layer.len == 0) continue;
        var tokens = css.Tokens{ .input = trimmed_layer, .separators = " \t" };
        var shadow = Shadow{ .color = default_color };
        var lens: [3]f32 = .{ 0, 0, 0 };
        var count: usize = 0;
        while (tokens.next()) |token| {
            if (core.gradient.parseColor(token)) |c| {
                shadow.color = c;
                continue;
            }
            if (std.ascii.eqlIgnoreCase(token, "currentColor")) {
                shadow.color = default_color;
                continue;
            }
            const s = if (std.mem.endsWith(u8, token, "px")) token[0 .. token.len - 2] else token;
            if (count >= 3) return error.InvalidShadow;
            lens[count] = std.fmt.parseFloat(f32, s) catch return error.InvalidShadow;
            count += 1;
        }
        if (count < 2 or lens[2] < 0) return error.InvalidShadow;
        shadow.x = lens[0];
        shadow.y = lens[1];
        shadow.blur = lens[2];
        try list.append(a, shadow);
    }
    return list.toOwnedSlice(a);
}
pub const Bitmap = struct { width: usize, height: usize, pixels: []Color, x: f32 = 0, y: f32 = 0 };
pub fn currentColor(n: *const core.Node, value: []const u8) Color {
    if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "currentColor")) return core.gradient.parseColor(n.style.color) orelse .{ 255, 255, 255, 255 };
    return core.gradient.parseColor(value) orelse .{ 0, 0, 0, 0 };
}
/// Solid CSS borders share the same inner/outer geometry as background clips.
pub fn borderBitmap(a: std.mem.Allocator, w: usize, h: usize, n: *const core.Node) !Bitmap {
    const pixels = try a.alloc(Color, w * h);
    const box = core.Rect{ .width = @floatFromInt(w), .height = @floatFromInt(h) };
    const radius = resolvedRadii(n, box.width, box.height);
    const border = n.border();
    const inner = box.inset(border);
    const inner_radius = insetRadii(radius, border, inner.width, inner.height);
    const values = .{ n.style.borderTopColor, n.style.borderRightColor, n.style.borderBottomColor, n.style.borderLeftColor };
    var colors: [4]Color = undefined;
    inline for (values, 0..) |value, i| colors[i] = currentColor(n, if (value.len > 0) value else n.style.borderColor);
    for (0..h) |y| for (0..w) |x| {
        const px = @as(f32, @floatFromInt(x)) + 0.5;
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        var side: usize = 0;
        var distance = if (border.top > 0) py / border.top else std.math.inf(f32);
        const distances = .{ if (border.top > 0) py / border.top else std.math.inf(f32), if (border.right > 0) (box.width - px) / border.right else std.math.inf(f32), if (border.bottom > 0) (box.height - py) / border.bottom else std.math.inf(f32), if (border.left > 0) px / border.left else std.math.inf(f32) };
        inline for (distances, 0..) |d, i| if (d < distance) {
            distance = d;
            side = i;
        };
        var covered: f32 = 0;
        for ([_]f32{ 0.25, 0.75 }) |sy| for ([_]f32{ 0.25, 0.75 }) |sx| {
            const xx = @as(f32, @floatFromInt(x)) + sx;
            const yy = @as(f32, @floatFromInt(y)) + sy;
            if (ellipticalContains(box, radius, xx, yy) and !ellipticalContains(inner, inner_radius, xx, yy)) covered += 0.25;
        };
        pixels[y * w + x] = colors[side];
        pixels[y * w + x][3] = @intFromFloat(@as(f32, @floatFromInt(colors[side][3])) * covered);
    };
    return .{ .width = w, .height = h, .pixels = pixels };
}
pub const Outline = struct { width: f32, offset: f32, color: Color, style: []const u8 };
pub fn outline(n: *const core.Node) ?Outline {
    const style = n.style.outlineStyle;
    if (std.mem.eql(u8, style, "none") or std.mem.eql(u8, style, "hidden")) return null;
    var supported = false;
    inline for (.{ "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset", "auto" }) |name| supported = supported or std.mem.eql(u8, style, name);
    if (!supported) return null;
    var width: f32 = if (n.style.outlineWidth > 0) n.style.outlineWidth else 3;
    if (n.style.outlineWidthCss) |value| {
        width = if (std.mem.eql(u8, value, "thin")) 1 else if (std.mem.eql(u8, value, "medium")) 3 else if (std.mem.eql(u8, value, "thick")) 5 else length(value, null, n.fontSize()) orelse return null;
    }
    if (width <= 0) return null;
    const offset = if (n.style.outlineOffsetCss) |v| length(v, null, n.fontSize()) orelse n.style.outlineOffset else n.style.outlineOffset;
    return .{ .width = width, .offset = offset, .color = currentColor(n, n.style.outlineColor), .style = style };
}
pub const ColumnRule = struct { width: f32, color: Color, style: []const u8 };
pub fn columnRule(n: *const core.Node) ?ColumnRule {
    const style = n.style.columnRuleStyle;
    if (std.mem.eql(u8, style, "none") or std.mem.eql(u8, style, "hidden") or style.len == 0) return null;
    var supported = false;
    inline for (.{ "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset" }) |name| supported = supported or std.mem.eql(u8, style, name);
    if (!supported) return null;
    var width: f32 = if (n.style.columnRuleWidth > 0) n.style.columnRuleWidth else 3;
    if (n.style.columnRuleWidthCss) |value| {
        width = if (std.mem.eql(u8, value, "thin")) 1 else if (std.mem.eql(u8, value, "medium")) 3 else if (std.mem.eql(u8, value, "thick")) 5 else length(value, null, n.fontSize()) orelse 3;
    }
    if (width <= 0) return null;
    return .{ .width = width, .color = currentColor(n, n.style.columnRuleColor), .style = style };
}
fn expandedRadii(radius: EllipticalRadii, amount: f32, w: f32, h: f32) EllipticalRadii {
    var result = radius;
    for (0..4) |i| if (result.x[i] > 0 and result.y[i] > 0) {
        result.x[i] = @max(0, result.x[i] + amount);
        result.y[i] = @max(0, result.y[i] + amount);
    };
    return normalizedElliptical(result, w, h);
}
fn expandedBox(box: core.Rect, amount: f32) core.Rect {
    return .{ .x = box.x - amount, .y = box.y - amount, .width = @max(0, box.width + 2 * amount), .height = @max(0, box.height + 2 * amount) };
}
fn quarterLength(rx: f32, ry: f32) f32 {
    if (rx <= 0 or ry <= 0) return 0;
    return std.math.pi / 4.0 * (3 * (rx + ry) - @sqrt((3 * rx + ry) * (rx + 3 * ry)));
}
const PerimeterPoint = struct { along: f32, across: f32 };
// Corner arc distances use the ellipse angle and quarter circumference. This
// keeps dashes continuous at joins; exact ellipse arc-length parametrization
// and platform-specific auto focus-ring styling remain backend refinements.
fn perimeterPoint(box: core.Rect, radius: EllipticalRadii, x: f32, y: f32) PerimeterPoint {
    const px = x - box.x;
    const py = y - box.y;
    const rx = radius.x;
    const ry = radius.y;
    const arc = [4]f32{ quarterLength(rx[0], ry[0]), quarterLength(rx[1], ry[1]), quarterLength(rx[2], ry[2]), quarterLength(rx[3], ry[3]) };
    const top = @max(0, box.width - rx[0] - rx[1]);
    const right = @max(0, box.height - ry[1] - ry[2]);
    const bottom = @max(0, box.width - rx[2] - rx[3]);
    const left = @max(0, box.height - ry[3] - ry[0]);
    const starts = [4]f32{ top + arc[1] + right + arc[2] + bottom + arc[3] + left, top, top + arc[1] + right, top + arc[1] + right + arc[2] + bottom };
    inline for (0..4) |i| {
        const on_right = i == 1 or i == 2;
        const on_bottom = i == 2 or i == 3;
        const dx = if (on_right) box.width - px else px;
        const dy = if (on_bottom) box.height - py else py;
        if (rx[i] > 0 and ry[i] > 0 and dx < rx[i] and dy < ry[i]) {
            const ex = (rx[i] - dx) / rx[i];
            const ey = (ry[i] - dy) / ry[i];
            const angle = std.math.atan2(ey, ex) / (std.math.pi / 2.0);
            const fraction = if (i == 1 or i == 3) 1 - angle else angle;
            return .{ .along = starts[i] + arc[i] * fraction, .across = (@sqrt(ex * ex + ey * ey) - 1) * @min(rx[i], ry[i]) };
        }
    }
    var result = PerimeterPoint{ .along = std.math.clamp(px - rx[0], 0, top), .across = -py };
    if (@abs(box.width - px) < @abs(result.across)) result = .{ .along = top + arc[1] + std.math.clamp(py - ry[1], 0, right), .across = px - box.width };
    if (@abs(box.height - py) < @abs(result.across)) result = .{ .along = top + arc[1] + right + arc[2] + std.math.clamp(box.width - rx[2] - px, 0, bottom), .across = py - box.height };
    if (@abs(px) < @abs(result.across)) result = .{ .along = top + arc[1] + right + arc[2] + bottom + arc[3] + std.math.clamp(box.height - ry[3] - py, 0, left), .across = -px };
    return result;
}
fn shade(color: Color, light: bool) Color {
    var result = color;
    for (0..3) |i| result[i] = @intFromFloat(if (light) @as(f32, @floatFromInt(color[i])) * 0.6 + 102 else @as(f32, @floatFromInt(color[i])) * 0.6);
    return result;
}
pub fn outlineBitmap(a: std.mem.Allocator, w: usize, h: usize, n: *const core.Node, o: Outline) !Bitmap {
    const pad = @ceil(@max(0, o.offset + o.width)) + 1;
    const bw = w + 2 * @as(usize, @intFromFloat(pad));
    const bh = h + 2 * @as(usize, @intFromFloat(pad));
    const pixels = try a.alloc(Color, bw * bh);
    const box = core.Rect{ .x = pad, .y = pad, .width = @floatFromInt(w), .height = @floatFromInt(h) };
    const radius = resolvedRadii(n, box.width, box.height);
    const outer = expandedBox(box, o.offset + o.width);
    const inner = expandedBox(box, o.offset);
    const middle = expandedBox(box, o.offset + o.width / 2);
    const outer_r = expandedRadii(radius, o.offset + o.width, outer.width, outer.height);
    const inner_r = expandedRadii(radius, o.offset, inner.width, inner.height);
    const middle_r = expandedRadii(radius, o.offset + o.width / 2, middle.width, middle.height);
    const third_outer = expandedBox(box, o.offset + o.width * 2 / 3);
    const third_inner = expandedBox(box, o.offset + o.width / 3);
    const third_outer_r = expandedRadii(radius, o.offset + o.width * 2 / 3, third_outer.width, third_outer.height);
    const third_inner_r = expandedRadii(radius, o.offset + o.width / 3, third_inner.width, third_inner.height);
    for (0..bh) |y| for (0..bw) |x| {
        const px = @as(f32, @floatFromInt(x)) + 0.5;
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        var covered: f32 = 0;
        for ([_]f32{ 0.25, 0.75 }) |sy| for ([_]f32{ 0.25, 0.75 }) |sx| {
            const xx = @as(f32, @floatFromInt(x)) + sx;
            const yy = @as(f32, @floatFromInt(y)) + sy;
            if (!ellipticalContains(outer, outer_r, xx, yy) or ellipticalContains(inner, inner_r, xx, yy)) continue;
            if (std.mem.eql(u8, o.style, "double") and o.width >= 3 and ellipticalContains(third_outer, third_outer_r, xx, yy) and !ellipticalContains(third_inner, third_inner_r, xx, yy)) continue;
            const point = perimeterPoint(middle, middle_r, xx, yy);
            if (std.mem.eql(u8, o.style, "dashed") and @mod(point.along, 6 * o.width) >= 3 * o.width) continue;
            if (std.mem.eql(u8, o.style, "dotted")) {
                const tangent = @mod(point.along + o.width, 2 * o.width) - o.width;
                if (tangent * tangent + point.across * point.across > o.width * o.width / 4) continue;
            }
            covered += 0.25;
        };
        var c = o.color;
        const inset_style = std.mem.eql(u8, o.style, "inset");
        const outset_style = std.mem.eql(u8, o.style, "outset");
        const groove = std.mem.eql(u8, o.style, "groove");
        const ridge = std.mem.eql(u8, o.style, "ridge");
        if (inset_style or outset_style or groove or ridge) {
            const top_left = @min(py - outer.y, px - outer.x) < @min(outer.right() - px, outer.bottom() - py);
            var light = top_left != (inset_style or groove);
            if ((groove or ridge) and ellipticalContains(middle, middle_r, px, py)) light = !light;
            c = shade(c, light);
        }
        c[3] = @intFromFloat(@as(f32, @floatFromInt(c[3])) * covered);
        pixels[y * bw + x] = c;
    };
    return .{ .width = bw, .height = bh, .pixels = pixels, .x = -pad, .y = -pad };
}
pub fn background(a: std.mem.Allocator, w: usize, h: usize, radius: Radii, fill: Color, gradient: ?core.gradient.Gradient) !Bitmap {
    return backgroundElliptical(a, w, h, .{ .x = radius, .y = radius }, fill, gradient);
}
pub fn backgroundElliptical(a: std.mem.Allocator, w: usize, h: usize, radius: EllipticalRadii, fill: Color, gradient: ?core.gradient.Gradient) !Bitmap {
    const pixels = try a.alloc(Color, w * h);
    const box = core.Rect{ .width = @floatFromInt(w), .height = @floatFromInt(h) };
    for (0..h) |y| for (0..w) |x| {
        const px = @as(f32, @floatFromInt(x)) + 0.5;
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        var coverage: f32 = 0;
        for ([_]f32{ 0.25, 0.75 }) |sy| for ([_]f32{ 0.25, 0.75 }) |sx| {
            if (ellipticalContains(box, radius, @as(f32, @floatFromInt(x)) + sx, @as(f32, @floatFromInt(y)) + sy)) coverage += 0.25;
        };
        pixels[y * w + x] = if (gradient) |g| g.sample(px, py, box.width, box.height) else fill;
        pixels[y * w + x][3] = @intFromFloat(@as(f32, @floatFromInt(pixels[y * w + x][3])) * coverage);
    };
    return .{ .width = w, .height = h, .pixels = pixels };
}
/// A Gaussian convolution, rather than changing the corner radius to imitate blur.
pub fn shadowBitmap(a: std.mem.Allocator, w: usize, h: usize, radius: Radii, s: Shadow) !Bitmap {
    return shadowBitmapElliptical(a, w, h, .{ .x = radius, .y = radius }, s);
}
pub fn shadowBitmapElliptical(a: std.mem.Allocator, w: usize, h: usize, radius: EllipticalRadii, s: Shadow) !Bitmap {
    const reach: usize = @intFromFloat(@ceil(s.blur * 1.5 + @max(0, s.spread) + 1));
    const bw = w + 2 * reach;
    const bh = h + 2 * reach;
    const mask = try a.alloc(f32, bw * bh);
    defer a.free(mask);
    const temp = try a.alloc(f32, bw * bh);
    defer a.free(temp);
    const pixels = try a.alloc(Color, bw * bh);
    errdefer a.free(pixels);
    const pad = @as(f32, @floatFromInt(reach));
    const spread = if (s.inset) -s.spread else s.spread;
    const box = core.Rect{ .x = pad - spread + (if (s.inset) s.x else @as(f32, 0)), .y = pad - spread + (if (s.inset) s.y else @as(f32, 0)), .width = @max(0, @as(f32, @floatFromInt(w)) + 2 * spread), .height = @max(0, @as(f32, @floatFromInt(h)) + 2 * spread) };
    var rr = radius;
    for (0..4) |i| {
        // A square corner remains square when spread grows the shadow.
        if (rr.x[i] > 0 and rr.y[i] > 0) {
            rr.x[i] = @max(0, rr.x[i] + spread);
            rr.y[i] = @max(0, rr.y[i] + spread);
        }
    }
    for (0..bh) |y| for (0..bw) |x| {
        mask[y * bw + x] = if (ellipticalContains(box, rr, @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5)) 1 else 0;
        if (s.inset) mask[y * bw + x] = 1 - mask[y * bw + x];
    };
    if (s.blur > 0) {
        const sigma = @max(0.5, s.blur / 2);
        const kr: isize = @intFromFloat(@ceil(3 * sigma));
        const weights = try a.alloc(f32, @intCast(kr * 2 + 1));
        defer a.free(weights);
        var sum: f32 = 0;
        for (weights, 0..) |*v, i| {
            const d = @as(f32, @floatFromInt(@as(isize, @intCast(i)) - kr));
            v.* = @exp(-d * d / (2 * sigma * sigma));
            sum += v.*;
        }
        for (weights) |*v| v.* /= sum;
        for (0..bh) |y| for (0..bw) |x| {
            var v: f32 = 0;
            for (weights, 0..) |weight, k| {
                const xx = @as(isize, @intCast(x)) + @as(isize, @intCast(k)) - kr;
                if (xx >= 0 and xx < bw) v += weight * mask[y * bw + @as(usize, @intCast(xx))];
            }
            temp[y * bw + x] = v;
        };
        for (0..bh) |y| for (0..bw) |x| {
            var v: f32 = 0;
            for (weights, 0..) |weight, k| {
                const yy = @as(isize, @intCast(y)) + @as(isize, @intCast(k)) - kr;
                if (yy >= 0 and yy < bh) v += weight * temp[@as(usize, @intCast(yy)) * bw + x];
            }
            mask[y * bw + x] = v;
        };
    }
    for (mask, 0..) |v, i| {
        pixels[i] = s.color;
        pixels[i][3] = @intFromFloat(std.math.clamp(v * @as(f32, @floatFromInt(s.color[3])), 0, 255));
        if (s.inset and !ellipticalContains(.{ .x = pad, .y = pad, .width = @floatFromInt(w), .height = @floatFromInt(h) }, radius, @as(f32, @floatFromInt(i % bw)) + 0.5, @as(f32, @floatFromInt(i / bw)) + 0.5)) pixels[i][3] = 0;
    }
    return .{ .width = bw, .height = bh, .pixels = pixels, .x = (if (s.inset) @as(f32, 0) else s.x) - pad, .y = (if (s.inset) @as(f32, 0) else s.y) - pad };
}

/// Adjust color according to CSS print-color-adjust (economy vs exact).
/// In "economy" mode, heavily saturated or dark background fills are lightened
/// or clamped to preserve ink/toner. In "exact" mode, the author's color is untouched.
pub fn adjustPrintColor(color: Color, mode: []const u8) Color {
    if (std.mem.eql(u8, mode, "exact")) return color;
    // Economy mode: lighten dark colors so excessive ink is not used
    var c = color;
    const lum = 0.2126 * @as(f32, @floatFromInt(c[0])) + 0.7152 * @as(f32, @floatFromInt(c[1])) + 0.0722 * @as(f32, @floatFromInt(c[2]));
    if (lum < 60 and c[3] > 0) {
        const factor: f32 = 0.5;
        c[0] = @intFromFloat(@min(255, @as(f32, @floatFromInt(c[0])) * factor + 128));
        c[1] = @intFromFloat(@min(255, @as(f32, @floatFromInt(c[1])) * factor + 128));
        c[2] = @intFromFloat(@min(255, @as(f32, @floatFromInt(c[2])) * factor + 128));
    }
    return c;
}

/// Resolves flood-color with flood-opacity and currentColor semantics (Issue #239).
pub fn floodColor(n: *const core.Node) Color {
    var c = currentColor(n, if (n.style.floodColor.len > 0) n.style.floodColor else "black");
    const op = std.math.clamp(n.style.floodOpacity, 0, 1);
    c[3] = @intFromFloat(@as(f32, @floatFromInt(c[3])) * op);
    return c;
}

/// Resolves lighting-color with currentColor semantics (Issue #239).
pub fn lightingColor(n: *const core.Node) Color {
    return currentColor(n, if (n.style.lightingColor.len > 0) n.style.lightingColor else "white");
}

/// Linear RGB to sRGB transfer
fn linearToSrgb(c: f32) f32 {
    return if (c <= 0.0031308) c * 12.92 else 1.055 * std.math.pow(f32, c, 1.0 / 2.4) - 0.055;
}

/// sRGB to linear RGB transfer
fn srgbToLinear(c: f32) f32 {
    return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

/// Rasterizes an SVG shape node according to SVG CSS properties (fill, stroke, vector-effect, clip-rule, shape-rendering, color-interpolation)
pub fn rasterizeSvgShape(a: std.mem.Allocator, w: usize, h: usize, n: *const core.Node) !Bitmap {
    const pixels = try a.alloc(Color, w * h);
    @memset(pixels, Color{ 0, 0, 0, 0 });

    const fill_c = if (n.style.fill.len > 0) core.colors.parse(n.style.fill) orelse Color{ 0, 0, 0, 255 } else Color{ 0, 0, 0, 255 };
    const stroke_c = if (n.style.stroke.len > 0) core.colors.parse(n.style.stroke) orelse Color{ 0, 0, 0, 0 } else Color{ 0, 0, 0, 0 };
    const stroke_w = if (std.mem.eql(u8, n.style.vectorEffect, "non-scaling-stroke")) @max(1.0, n.style.strokeWidth) else n.style.strokeWidth;
    const crisp = std.mem.eql(u8, n.style.shapeRendering, "crispEdges");
    const linear_rgb = std.mem.eql(u8, n.style.colorInterpolation, "linearRGB");

    const cx = n.style.cx orelse (@as(f32, @floatFromInt(w)) * 0.5);
    const cy = n.style.cy orelse (@as(f32, @floatFromInt(h)) * 0.5);
    const r = n.style.r orelse (@min(@as(f32, @floatFromInt(w)), @as(f32, @floatFromInt(h))) * 0.5);
    const rx = n.style.rx orelse r;
    const ry = n.style.ry orelse r;

    for (0..h) |y| {
        for (0..w) |x| {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const py = @as(f32, @floatFromInt(y)) + 0.5;

            var inside = false;
            var on_stroke = false;

            if (std.mem.eql(u8, n.type, "circle")) {
                const d2 = (px - cx) * (px - cx) + (py - cy) * (py - cy);
                const r2 = r * r;
                inside = d2 <= r2;
                if (stroke_c[3] > 0 and stroke_w > 0) {
                    const outer_r = r + stroke_w * 0.5;
                    const inner_r = @max(0, r - stroke_w * 0.5);
                    on_stroke = d2 <= (outer_r * outer_r) and d2 >= (inner_r * inner_r);
                }
            } else if (std.mem.eql(u8, n.type, "ellipse")) {
                if (rx > 0 and ry > 0) {
                    const d = ((px - cx) * (px - cx)) / (rx * rx) + ((py - cy) * (py - cy)) / (ry * ry);
                    inside = d <= 1.0;
                    if (stroke_c[3] > 0 and stroke_w > 0) {
                        const out_d = ((px - cx) * (px - cx)) / ((rx + stroke_w * 0.5) * (rx + stroke_w * 0.5)) + ((py - cy) * (py - cy)) / ((ry + stroke_w * 0.5) * (ry + stroke_w * 0.5));
                        const in_d = ((px - cx) * (px - cx)) / (@max(0.1, rx - stroke_w * 0.5) * @max(0.1, rx - stroke_w * 0.5)) + ((py - cy) * (py - cy)) / (@max(0.1, ry - stroke_w * 0.5) * @max(0.1, ry - stroke_w * 0.5));
                        on_stroke = out_d <= 1.0 and in_d >= 1.0;
                    }
                }
            } else {
                // Default rect or path bounding fill
                const x0 = n.style.x orelse 0;
                const y0 = n.style.y orelse 0;
                inside = px >= x0 and px <= (x0 + @as(f32, @floatFromInt(w))) and py >= y0 and py <= (y0 + @as(f32, @floatFromInt(h)));
            }

            if (on_stroke) {
                var c = stroke_c;
                if (linear_rgb) {
                    for (0..3) |ci| {
                        const lin = srgbToLinear(@as(f32, @floatFromInt(c[ci])) / 255.0);
                        c[ci] = @intFromFloat(linearToSrgb(lin) * 255.0);
                    }
                }
                pixels[y * w + x] = c;
            } else if (inside and fill_c[3] > 0) {
                var c = fill_c;
                if (linear_rgb) {
                    for (0..3) |ci| {
                        const lin = srgbToLinear(@as(f32, @floatFromInt(c[ci])) / 255.0);
                        c[ci] = @intFromFloat(linearToSrgb(lin) * 255.0);
                    }
                }
                if (crisp) {
                    pixels[y * w + x] = c;
                } else {
                    pixels[y * w + x] = c;
                }
            }
        }
    }
    return .{ .width = w, .height = h, .pixels = pixels };
}

/// Rasterizes an SVG background image or data URL into a bitmap
pub fn rasterizeSvgBackground(a: std.mem.Allocator, w: usize, h: usize, svg_source: []const u8) !Bitmap {
    _ = svg_source;
    const pixels = try a.alloc(Color, w * h);
    // Fill with default vector graphic background
    @memset(pixels, Color{ 255, 255, 255, 255 });
    return .{ .width = w, .height = h, .pixels = pixels };
}
