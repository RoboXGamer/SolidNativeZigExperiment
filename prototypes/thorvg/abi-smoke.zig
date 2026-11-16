extern fn puts([*:0]const u8) c_int;
// ThorVG's C header uses C enum-sized int returns and opaque pointer handles.
// Zig 0.17 removed @cImport; this small explicit ABI surface avoids a generator.
extern fn tvg_engine_init(c_uint) c_int;
extern fn tvg_engine_term() c_int;
extern fn tvg_swcanvas_create(c_int) ?*anyopaque;
extern fn tvg_canvas_destroy(?*anyopaque) c_int;
extern fn tvg_swcanvas_set_target(?*anyopaque, [*]u32, u32, u32, u32, c_int) c_int;
extern fn tvg_shape_new() ?*anyopaque;
extern fn tvg_shape_append_rect(?*anyopaque, f32, f32, f32, f32, f32, f32, bool) c_int;
extern fn tvg_shape_set_fill_color(?*anyopaque, u8, u8, u8, u8) c_int;
extern fn tvg_canvas_add(?*anyopaque, ?*anyopaque) c_int;
extern fn tvg_canvas_update(?*anyopaque) c_int;
extern fn tvg_canvas_draw(?*anyopaque, bool) c_int;
extern fn tvg_canvas_sync(?*anyopaque) c_int;
fn ok(r: c_int) void {
    if (r != 0) @panic("ThorVG C ABI error");
}
pub fn main() void {
    ok(tvg_engine_init(0));
    defer ok(tvg_engine_term());
    const canvas = tvg_swcanvas_create(2);
    defer ok(tvg_canvas_destroy(canvas));
    var pixels: [1024]u32 = @splat(0);
    ok(tvg_swcanvas_set_target(canvas, &pixels, 32, 32, 32, 0));
    const shape = tvg_shape_new();
    ok(tvg_shape_append_rect(shape, 4, 4, 24, 24, 3, 3, true));
    ok(tvg_shape_set_fill_color(shape, 30, 200, 70, 255));
    ok(tvg_canvas_add(canvas, shape));
    ok(tvg_canvas_update(canvas));
    ok(tvg_canvas_draw(canvas, true));
    ok(tvg_canvas_sync(canvas));
    if (pixels[16 * 32 + 16] != 0xff46c81e or pixels[0] != 0) @panic("C ABI pixel mismatch");
    _ = puts("PASS Zig 0.17 C ABI lifecycle and rounded rectangle pixels");
}
