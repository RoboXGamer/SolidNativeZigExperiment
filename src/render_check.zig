//! Native OpenGL framebuffer regressions, run by zig build test-native.
const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui_core");
const Renderer = @import("renderer.zig").Renderer;
fn draw(_: *anyopaque, _: *ui.Scene, item: ui.Item, _: std.mem.Allocator) !void {
    if (std.mem.eql(u8, item.node.type, "text")) rl.drawRectangle(@intFromFloat(item.bounds.x), @intFromFloat(item.bounds.y), 4, 4, .white);
}
fn frame(renderer: *Renderer, json: []const u8) !rl.Image {
    var scene = try ui.Scene.init(std.heap.page_allocator, json, 128, 128);
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var dummy: u8 = 0;
    rl.beginDrawing();
    rl.clearBackground(.black);
    try renderer.render(&scene, &dummy, draw, arena.allocator());
    rl.endDrawing();
    var image = try rl.loadImageFromTexture(renderer.targets.items[3].texture);
    rl.imageFlipVertical(&image);
    return image;
}
fn check(condition: bool, name: []const u8) !void {
    if (!condition) {
        std.debug.print("FAIL native: {s}\n", .{name});
        return error.NativePixelMismatch;
    }
    std.debug.print("PASS native: {s}\n", .{name});
}
pub fn main() !void {
    const backend = @import("text_backend.zig");
    const latin = backend.measure(null, "AV ffi", 24);
    const indic = backend.measure(null, "नमस्ते दुनिया", 24);
    const arabic = backend.measure(null, "مرحبا بالعالم", 24);
    try check(latin.width > 0 and latin.ascent > 0 and latin.descent > 0 and indic.width > 0 and arabic.width > 0, "native shaping metrics for Latin Indic Arabic");
    rl.setTraceLogLevel(.warning);
    rl.setConfigFlags(.{ .window_hidden = true });
    rl.initWindow(128, 128, "Native paint regression");
    defer rl.closeWindow();
    var renderer = try Renderer.init(std.heap.page_allocator);
    defer renderer.deinit();
    const mapped_image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"column","style":{"width":64,"height":64,"backgroundColor":"oklch(0.7 0.4 30)"}}]}
    );
    const mapped_pixel = rl.getImageColor(mapped_image, 20, 20);
    try check(mapped_pixel.r == 255 and @abs(@as(i16, mapped_pixel.g) - 88) <= 1 and @abs(@as(i16, mapped_pixel.b) - 67) <= 1, "OKLCH mapped scene background framebuffer reference");
    rl.unloadImage(mapped_image);
    var text_cache = backend.Cache.init(std.heap.page_allocator);
    defer text_cache.deinit();
    // Exercise the same shaped glyph rasterizer used by application paint.
    rl.beginDrawing();
    try text_cache.draw("नमस्ते — مرحبا", 0, 0, 24, .white);
    rl.endDrawing();
    try check(text_cache.textures.count() == 1, "native shaped glyph raster upload");
    var image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"column","style":{"position":"absolute","width":80,"height":80,"backgroundGradient":"linear-gradient(90deg, #ff0000, #00ff00 50%, #0000ff)"}}]}
    );
    const center = rl.getImageColor(image, 40, 40);
    try check(center.g > 220 and center.r < 30 and center.b < 30, "intermediate gradient stop");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"column","style":{"position":"absolute","width":80,"height":80,"backgroundGradient":"radial-gradient(circle closest-side, #ffffff, #000000)"}}]}
    );
    const middle = rl.getImageColor(image, 40, 40);
    const edge = rl.getImageColor(image, 78, 40);
    try check(middle.r > 220 and edge.r < 40, "radial center and edge");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"column","style":{"position":"absolute","width":80,"height":80,"backgroundGradient":"conic-gradient(from 0deg, #ff0000, #00ff00 50%, #0000ff)"}}]}
    );
    const top = rl.getImageColor(image, 40, 5);
    const bottom = rl.getImageColor(image, 40, 75);
    try check(top.r > 180 and bottom.g > 180, "conic angular colors");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"column","style":{"position":"absolute","left":20,"top":20,"width":40,"height":40,"overflow":"hidden","borderRadius":18,"opacity":0.5,"backgroundColor":"#ff0000"},"children":[{"id":3,"type":"column","style":{"width":40,"height":40,"backgroundColor":"#0000ff"}}]}]}
    );
    const overlap = rl.getImageColor(image, 40, 40);
    const corner = rl.getImageColor(image, 20, 20);
    try check(overlap.a > 115 and overlap.a < 140 and overlap.r < 10 and overlap.b > 110, "subtree opacity composited once");
    try check(corner.a < 10, "rounded descendant clipping");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"column","style":{"position":"absolute","left":20,"top":20,"width":20,"height":20,"transform":"translate(30px, 0px) scale(2)","transformOrigin":"0 0","backgroundColor":"#ff0000"},"children":[{"id":3,"type":"text","style":{"width":4,"height":4}}]}]}
    );
    const transformed = rl.getImageColor(image, 51, 21);
    const scaled = rl.getImageColor(image, 85, 50);
    const original = rl.getImageColor(image, 21, 21);
    try check(transformed.r > 220 and transformed.g > 220 and scaled.r > 220 and original.a < 10, "world transform applies to children and content");
    rl.unloadImage(image);
    std.debug.print("Native framebuffer regressions passed\n", .{});
}
