const std = @import("std");
const ui = @import("ui_core");
const rl = @import("raylib");
const NativeMetrics = extern struct { width: f32, height: f32, ascent: f32, descent: f32, leading: f32 };
extern fn ui_text_measure([*]const u8, usize, f32, *NativeMetrics) c_int;
extern fn ui_text_raster([*]const u8, usize, f32, *c_int, *c_int) ?[*]u8;
extern fn ui_text_free(*anyopaque) void;
extern fn ui_text_position([*]const u8, usize, f32, f32) c_int;
pub extern fn ui_text_ime_position(?*anyopaque, c_int, c_int) void;
pub fn measure(_: ?*anyopaque, text: []const u8, size: f32) ui.Metrics {
    var m: NativeMetrics = undefined;
    if (ui_text_measure(text.ptr, text.len, size, &m) != 0) return .{ .width = m.width, .height = m.height, .ascent = m.ascent, .descent = m.descent, .leading = m.leading };
    return ui.text.estimate(text, size);
}
pub fn position(_: ?*anyopaque, text: []const u8, x: f32, size: f32) usize {
    return @intCast(@max(0, ui_text_position(text.ptr, text.len, size, x)));
}
pub const Cache = struct {
    allocator: std.mem.Allocator,
    textures: std.AutoHashMap(u64, rl.Texture2D),
    pub fn init(a: std.mem.Allocator) Cache {
        return .{ .allocator = a, .textures = std.AutoHashMap(u64, rl.Texture2D).init(a) };
    }
    pub fn deinit(self: *Cache) void {
        var it = self.textures.valueIterator();
        while (it.next()) |t| rl.unloadTexture(t.*);
        self.textures.deinit();
    }
    pub fn draw(self: *Cache, text: []const u8, x: f32, y: f32, size: f32, color: rl.Color) !void {
        if (text.len == 0) return;
        var hash = std.hash.Wyhash.init(0);
        hash.update(text);
        hash.update(std.mem.asBytes(&size));
        const key = hash.final();
        if (!self.textures.contains(key)) {
            var w: c_int = 0;
            var h: c_int = 0;
            const pixels = ui_text_raster(text.ptr, text.len, size, &w, &h) orelse return error.TextRasterFailed;
            defer ui_text_free(@ptrCast(pixels));
            const image = rl.Image{ .data = @ptrCast(pixels), .width = w, .height = h, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
            const texture = try rl.loadTextureFromImage(image);
            errdefer rl.unloadTexture(texture);
            // Bound cache growth under rapidly changing counters / HMR.
            if (self.textures.count() >= 512) {
                var it = self.textures.valueIterator();
                while (it.next()) |t| rl.unloadTexture(t.*);
                self.textures.clearRetainingCapacity();
            }
            try self.textures.put(key, texture);
        }
        rl.drawTextureV(self.textures.get(key).?, .{ .x = x, .y = y }, color);
    }
};
