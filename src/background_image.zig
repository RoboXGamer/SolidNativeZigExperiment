//! CSS raster URL backgrounds. Assets are embedded by the Vite CSS compiler.
const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui_core");
fn length(value: []const u8, basis: f32, font: f32) ?f32 {
    const r = ui.sizing.resolve(value, .{ .percentage = basis, .font_size = font }) catch return null;
    return switch (r) {
        .length => |v| v,
        else => null,
    };
}
fn position(token: []const u8, space: f32, font: f32) f32 {
    if (std.mem.eql(u8, token, "center")) return space / 2;
    if (std.mem.eql(u8, token, "right") or std.mem.eql(u8, token, "bottom")) return space;
    if (std.mem.eql(u8, token, "left") or std.mem.eql(u8, token, "top")) return 0;
    return length(token, space, font) orelse 0;
}
pub fn paint(a: std.mem.Allocator, bitmap: ui.paint.Bitmap, n: *const ui.Node, radius: ui.paint.EllipticalRadii) !void {
    var url = std.mem.trim(u8, n.style.backgroundImage, " \t\r\n");
    if (url.len == 0 or std.mem.eql(u8, url, "none")) return;
    if (!std.mem.startsWith(u8, url, "url(") or !std.mem.endsWith(u8, url, ")")) return error.UnsupportedBackgroundImage;
    url = std.mem.trim(u8, url[4 .. url.len - 1], " \t\r\n\"'");
    const comma = std.mem.indexOfScalar(u8, url, ',') orelse return error.InvalidImageUrl;
    const header = url[0..comma];
    if (!std.mem.startsWith(u8, header, "data:image/") or !std.mem.endsWith(u8, header, ";base64")) return error.UnsupportedImageUrl;
    const extension: [:0]const u8 = if (std.mem.indexOf(u8, header, "png") != null) ".png" else if (std.mem.indexOf(u8, header, "jpeg") != null) ".jpg" else if (std.mem.indexOf(u8, header, "webp") != null) ".webp" else if (std.mem.indexOf(u8, header, "svg") != null) ".svg" else if (std.mem.indexOf(u8, header, "gif") != null) ".gif" else return error.UnsupportedImageFormat;
    const decoder = std.base64.standard.Decoder;
    const encoded = url[comma + 1 ..];
    const bytes = try a.alloc(u8, try decoder.calcSizeForSlice(encoded));
    defer a.free(bytes);
    try decoder.decode(bytes, encoded);
    var image = try rl.loadImageFromMemory(extension, bytes);
    defer rl.unloadImage(image);
    rl.imageFormat(&image, .uncompressed_r8g8b8a8);
    const pixels: [*]const [4]u8 = @ptrCast(@alignCast(image.data));
    const box = ui.Rect{ .width = @floatFromInt(bitmap.width), .height = @floatFromInt(bitmap.height) };
    const origin = if (std.mem.eql(u8, n.style.backgroundOrigin, "border-box")) box else if (std.mem.eql(u8, n.style.backgroundOrigin, "content-box")) n.contentBox(box) else n.paddingBox(box);
    const clip = if (std.mem.eql(u8, n.style.backgroundClip, "content-box")) n.contentBox(box) else if (std.mem.eql(u8, n.style.backgroundClip, "padding-box")) n.paddingBox(box) else box;
    const iw: f32 = @floatFromInt(image.width);
    const ih: f32 = @floatFromInt(image.height);
    var w = iw;
    var h = ih;
    const size = n.style.backgroundSize;
    if (std.mem.eql(u8, size, "cover") or std.mem.eql(u8, size, "contain")) {
        const factor = if (std.mem.eql(u8, size, "cover")) @max(origin.width / iw, origin.height / ih) else @min(origin.width / iw, origin.height / ih);
        w *= factor;
        h *= factor;
    } else {
        var tokens = std.mem.tokenizeAny(u8, size, " \t");
        const x = tokens.next() orelse "auto";
        const y = tokens.next() orelse "auto";
        const ww = length(x, origin.width, n.fontSize());
        const hh = length(y, origin.height, n.fontSize());
        if (ww) |v| w = v;
        if (hh) |v| h = v;
        if (ww != null and hh == null) h = w * ih / iw;
        if (hh != null and ww == null) w = h * iw / ih;
    }
    if (w <= 0 or h <= 0) return;
    var positions = std.mem.tokenizeAny(u8, n.style.backgroundPosition, " \t");
    var px = positions.next() orelse "0%";
    var py = positions.next() orelse "center";
    if (std.mem.eql(u8, px, "top") or std.mem.eql(u8, px, "bottom")) {
        const swap = px;
        px = py;
        py = swap;
    }
    const x0 = origin.x + position(px, origin.width - w, n.fontSize());
    const y0 = origin.y + position(py, origin.height - h, n.fontSize());
    const repeat = n.style.backgroundRepeat;
    const rx = std.mem.eql(u8, repeat, "repeat") or std.mem.eql(u8, repeat, "repeat-x") or std.mem.startsWith(u8, repeat, "repeat ");
    const ry = std.mem.eql(u8, repeat, "repeat") or std.mem.eql(u8, repeat, "repeat-y") or std.mem.endsWith(u8, repeat, " repeat");
    for (0..bitmap.height) |y| for (0..bitmap.width) |x| {
        const xx: f32 = @as(f32, @floatFromInt(x)) + 0.5;
        const yy: f32 = @as(f32, @floatFromInt(y)) + 0.5;
        if (xx < clip.x or xx >= clip.x + clip.width or yy < clip.y or yy >= clip.y + clip.height) continue;
        if (!ui.paint.ellipticalContains(box, radius, xx, yy)) continue;
        var sx = xx - x0;
        var sy = yy - y0;
        if (rx) sx = @mod(sx, w);
        if (ry) sy = @mod(sy, h);
        if (sx < 0 or sx >= w or sy < 0 or sy >= h) continue;
        const ix: usize = @intFromFloat(@min(iw - 1, @floor(sx / w * iw)));
        const iy: usize = @intFromFloat(@min(ih - 1, @floor(sy / h * ih)));
        const source = pixels[iy * @as(usize, @intCast(image.width)) + ix];
        const dest = &bitmap.pixels[y * bitmap.width + x];
        const alpha = @as(f32, @floatFromInt(source[3])) / 255;
        const da = @as(f32, @floatFromInt(dest[3])) / 255;
        const out = alpha + da * (1 - alpha);
        if (out > 0) for (0..3) |c| {
            dest[c] = @intFromFloat((@as(f32, @floatFromInt(source[c])) * alpha + @as(f32, @floatFromInt(dest[c])) * da * (1 - alpha)) / out);
        };
        dest[3] = @intFromFloat(out * 255);
    };
}
