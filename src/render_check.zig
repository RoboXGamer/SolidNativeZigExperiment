//! Native OpenGL framebuffer regressions, run by zig build test-native.
const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui_core");
const Renderer = @import("renderer.zig").Renderer;
extern fn ui_cursor_update([*]const u8, usize, c_int, c_int) void;
extern fn ui_cursor_shutdown() void;
extern fn ui_cursor_start() c_int;
extern "user32" fn GetCursor() ?*anyopaque;
extern "user32" fn SendMessageW(?*anyopaque, u32, usize, isize) isize;
fn draw(_: *anyopaque, _: *ui.Scene, item: ui.Item, _: std.mem.Allocator) !void {
    if (std.mem.eql(u8, item.node.type, "text")) rl.drawRectangle(@intFromFloat(item.bounds.x), @intFromFloat(item.bounds.y), 4, 4, if (std.mem.eql(u8, item.node.text, "coverage")) .{ .r = 255, .g = 255, .b = 255, .a = 128 } else .white);
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
    const latin = backend.measureStyled(null, "AV ffi", 24, .{});
    const indic = backend.measureStyled(null, "नमस्ते दुनिया", 24, .{});
    const arabic = backend.measureStyled(null, "مرحبا بالعالم", 24, .{});
    try check(latin.width > 0 and latin.ascent > 0 and latin.descent > 0 and indic.width > 0 and arabic.width > 0, "native shaping metrics for Latin Indic Arabic");
    rl.setTraceLogLevel(.warning);
    rl.setConfigFlags(.{ .window_hidden = true });
    rl.initWindow(128, 128, "Native paint regression");
    defer rl.closeWindow();
    defer ui_cursor_shutdown();
    try check(ui_cursor_start() == 1, "persistent cursor message ownership");
    ui_cursor_update("pointer", 7, 0, 0);
    const pointer = GetCursor();
    const hwnd: ?*anyopaque = rl.getWindowHandle();
    ui_cursor_update("text", 4, 1, 0);
    const text_cursor = GetCursor();
    _ = SendMessageW(hwnd, 0x20, @intFromPtr(hwnd), 1 | (0x200 << 16));
    try check(GetCursor() == text_cursor and text_cursor != pointer, "text cursor persists through WM_SETCURSOR");
    _ = SendMessageW(hwnd, 0x20, @intFromPtr(hwnd), 2 | (0x200 << 16));
    try check(GetCursor() != text_cursor, "non-client cursor remains owned by the window system");
    ui_cursor_update("auto", 4, 1, 1);
    try check(GetCursor() == pointer, "clickable control cursor takes precedence over child text");
    const cursor_url = "url(\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAHUlEQVR4nGNQDYj7j4ylTJ1RMAMdFKALoGuggwIAkDFsYfnTE3cAAAAASUVORK5CYII=\") 0 0, pointer";
    ui_cursor_update(cursor_url, cursor_url.len, 0, 0);
    try check(GetCursor() != null and GetCursor() != pointer, "CSS embedded raster cursor creation");
    const raster_cursor = GetCursor();
    _ = SendMessageW(hwnd, 0x20, @intFromPtr(hwnd), 1 | (0x200 << 16));
    try check(GetCursor() == raster_cursor, "raster cursor persists through WM_SETCURSOR");
    ui_cursor_update("none", 4, 0, 0);
    _ = SendMessageW(hwnd, 0x20, @intFromPtr(hwnd), 1 | (0x200 << 16));
    try check(GetCursor() == null, "hidden cursor persists through WM_SETCURSOR");
    var renderer = try Renderer.init(std.heap.page_allocator);
    defer renderer.deinit();
    var text_cache = backend.Cache.init(std.heap.page_allocator);
    defer text_cache.deinit();
    const first_metrics = backend.measureCached(&text_cache, "X (YOU)", 11, .{});
    for (0..100) |_| _ = backend.measureCached(&text_cache, "X (YOU)", 11, .{});
    try check(text_cache.measurement_runs == 1, "repeated text measurement reuses native shaping metrics");
    const spaced_metrics = backend.measureCached(&text_cache, "X (YOU)", 11, .{ .letter_spacing = 2 });
    try check(text_cache.measurement_runs == 2 and spaced_metrics.width > first_metrics.width, "typography changes invalidate cached shaping metrics");
    // Exercise the same shaped glyph rasterizer used by application paint.
    rl.beginDrawing();
    try text_cache.drawStyled("नमस्ते — مرحبا", 0, 0, 24, .white, .{});
    rl.endDrawing();
    try check(text_cache.textures.count() == 1, "native shaped glyph raster upload");
    var glyphs = text_cache.textures.valueIterator();
    const glyph_image = try rl.loadImageFromTexture(glyphs.next().?.*);
    defer rl.unloadImage(glyph_image);
    var partial_coverage: usize = 0;
    for (0..@intCast(glyph_image.height)) |y| for (0..@intCast(glyph_image.width)) |x| {
        const alpha = rl.getImageColor(glyph_image, @intCast(x), @intCast(y)).a;
        if (alpha > 0 and alpha < 255) partial_coverage += 1;
    };
    try check(partial_coverage > 20, "glyph raster contains grayscale edge coverage");
    const coverage = try frame(&renderer,
        \\{"id":1,"type":"root","children":[{"id":2,"type":"text","text":"coverage"}]}
    );
    try check(@abs(@as(i32, rl.getImageColor(coverage, 1, 1).a) - 128) <= 1, "transparent surfaces preserve source edge coverage");
    try check(renderer.direct_items == 2 and renderer.masked_items == 0, "unclipped items draw without per-item offscreen passes");
    rl.unloadImage(coverage);
    const clipped_coverage = try frame(&renderer,
        \\{"id":1,"type":"root","children":[{"id":2,"type":"div","style":{"width":40,"height":40,"overflow":"hidden"},"children":[{"id":3,"type":"text","text":"coverage"}]}]}
    );
    defer rl.unloadImage(clipped_coverage);
    try check(@abs(@as(i32, rl.getImageColor(clipped_coverage, 1, 1).a) - 128) <= 1, "clipped content preserves source edge coverage");
    var image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"div","style":{"position":"absolute","width":80,"height":80,"backgroundGradient":"linear-gradient(90deg, #ff0000, #00ff00 50%, #0000ff)"}}]}
    );
    const center = rl.getImageColor(image, 40, 40);
    try check(center.g > 220 and center.r < 30 and center.b < 30, "intermediate gradient stop");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"div","style":{"position":"absolute","width":80,"height":80,"backgroundGradient":"radial-gradient(circle closest-side, #ffffff, #000000)"}}]}
    );
    const middle = rl.getImageColor(image, 40, 40);
    const edge = rl.getImageColor(image, 78, 40);
    try check(middle.r > 220 and edge.r < 40, "radial center and edge");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"div","style":{"position":"absolute","width":80,"height":80,"backgroundGradient":"conic-gradient(from 0deg, #ff0000, #00ff00 50%, #0000ff)"}}]}
    );
    const top = rl.getImageColor(image, 40, 5);
    const bottom = rl.getImageColor(image, 40, 75);
    try check(top.r > 180 and bottom.g > 180, "conic angular colors");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"div","style":{"position":"absolute","left":20,"top":20,"width":40,"height":40,"overflow":"hidden","borderRadiusCss":"18px","opacity":0.5,"backgroundColor":"#ff0000"},"children":[{"id":3,"type":"div","style":{"width":40,"height":40,"backgroundColor":"#0000ff"}}]}]}
    );
    const overlap = rl.getImageColor(image, 40, 40);
    const corner = rl.getImageColor(image, 20, 20);
    try check(overlap.a > 115 and overlap.a < 140 and overlap.r < 10 and overlap.b > 110, "subtree opacity composited once");
    try check(corner.a < 10, "rounded descendant clipping");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"div","style":{"position":"absolute","left":20,"top":20,"width":20,"height":20,"transform":"translate(30px, 0px) scale(2)","transformOrigin":"0 0","backgroundColor":"#ff0000"},"children":[{"id":3,"type":"text","style":{"width":4,"height":4}}]}]}
    );
    const transformed = rl.getImageColor(image, 51, 21);
    const scaled = rl.getImageColor(image, 85, 50);
    const original = rl.getImageColor(image, 21, 21);
    try check(transformed.r > 220 and transformed.g > 220 and scaled.r > 220 and original.a < 10, "world transform applies to children and content");
    try check(renderer.isolated_contexts == 0, "transforms preserve ordering without allocating group surfaces");
    rl.unloadImage(image);
    image = try frame(&renderer,
        \\{"id":1,"type":"root","style":{"width":128,"height":128},"children":[{"id":2,"type":"div","style":{"position":"absolute","width":80,"height":80,"backgroundImage":"url(\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAHUlEQVR4nGNQDYj7j4ylTJ1RMAMdFKALoGuggwIAkDFsYfnTE3cAAAAASUVORK5CYII=\")","backgroundSize":"32px 32px","backgroundRepeat":"repeat","borderRadiusCss":"12px"}}]}
    );
    const image_light = rl.getImageColor(image, 8, 8);
    const image_dark = rl.getImageColor(image, 24, 8);
    const image_repeat = rl.getImageColor(image, 40, 8);
    try check(image_light.g == 80 and image_dark.g == 53 and image_repeat.g == 80, "CSS embedded PNG decoding sizing and repeat");
    try check(rl.getImageColor(image, 0, 0).a == 0, "CSS image rounded corner clipping");
    rl.unloadImage(image);
    std.debug.print("Native framebuffer regressions passed\n", .{});
}
