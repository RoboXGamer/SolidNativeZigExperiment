//! Backend-independent paint geometry and RGBA rasterization for cached effects.
const std = @import("std");
const core = @import("root.zig");
const css = @import("css_syntax.zig");
pub const Color = [4]u8;
pub const Radii = [4]f32; // top-left, top-right, bottom-right, bottom-left

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
    if (!box.contains(x, y)) return false;
    const r = normalized(radius, box.width, box.height);
    const px = x - box.x;
    const py = y - box.y;
    const right = px > box.width / 2;
    const bottom = py > box.height / 2;
    const cr = r[if (bottom) (if (right) @as(usize, 2) else 3) else (if (right) @as(usize, 1) else 0)];
    const cx = if (right) box.width - cr else cr;
    const cy = if (bottom) box.height - cr else cr;
    if (@abs(px - cx) < cr and @abs(py - cy) < cr) return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= cr * cr;
    return true;
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
pub const Bitmap = struct { width: usize, height: usize, pixels: []Color, x: f32 = 0, y: f32 = 0 };
pub fn background(a: std.mem.Allocator, w: usize, h: usize, radius: Radii, fill: Color, gradient: ?core.gradient.Gradient) !Bitmap {
    const pixels = try a.alloc(Color, w * h);
    const box = core.Rect{ .width = @floatFromInt(w), .height = @floatFromInt(h) };
    for (0..h) |y| for (0..w) |x| {
        const px = @as(f32, @floatFromInt(x)) + 0.5;
        const py = @as(f32, @floatFromInt(y)) + 0.5;
        pixels[y * w + x] = if (!roundedContains(box, radius, px, py)) .{ 0, 0, 0, 0 } else if (gradient) |g| g.sample(px, py, box.width, box.height) else fill;
    };
    return .{ .width = w, .height = h, .pixels = pixels };
}
/// A Gaussian convolution, rather than changing the corner radius to imitate blur.
pub fn shadowBitmap(a: std.mem.Allocator, w: usize, h: usize, radius: Radii, s: Shadow) !Bitmap {
    const reach: usize = @intFromFloat(@ceil(s.blur * 1.5 + @max(0, s.spread) + 1));
    const bw = w + 2 * reach;
    const bh = h + 2 * reach;
    const mask = try a.alloc(f32, bw * bh);
    defer a.free(mask);
    const temp = try a.alloc(f32, bw * bh);
    defer a.free(temp);
    const pixels = try a.alloc(Color, bw * bh);
    const pad = @as(f32, @floatFromInt(reach));
    const spread = if (s.inset) -s.spread else s.spread;
    const box = core.Rect{ .x = pad - spread + (if (s.inset) s.x else @as(f32, 0)), .y = pad - spread + (if (s.inset) s.y else @as(f32, 0)), .width = @max(0, @as(f32, @floatFromInt(w)) + 2 * spread), .height = @max(0, @as(f32, @floatFromInt(h)) + 2 * spread) };
    var rr = radius;
    for (&rr) |*r| r.* = @max(0, r.* + spread);
    for (0..bh) |y| for (0..bw) |x| {
        mask[y * bw + x] = if (roundedContains(box, rr, @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5)) 1 else 0;
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
        if (s.inset and !roundedContains(.{ .x = pad, .y = pad, .width = @floatFromInt(w), .height = @floatFromInt(h) }, radius, @as(f32, @floatFromInt(i % bw)) + 0.5, @as(f32, @floatFromInt(i / bw)) + 0.5)) pixels[i][3] = 0;
    }
    return .{ .width = bw, .height = bh, .pixels = pixels, .x = (if (s.inset) @as(f32, 0) else s.x) - pad, .y = (if (s.inset) @as(f32, 0) else s.y) - pad };
}
