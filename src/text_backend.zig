const std = @import("std");
const ui = @import("ui_core");
const rl = @import("raylib");
const NativeMetrics = extern struct { width: f32, height: f32, ascent: f32, descent: f32, leading: f32 };
const Typography = ui.text.Typography;
const NativeStyle = extern struct {
    family: [*]const u8,
    family_length: usize,
    style: [*]const u8,
    style_length: usize,
    language: [*]const u8,
    language_length: usize,
    transform: [*]const u8,
    transform_length: usize,
    feature_settings: [*]const u8,
    feature_settings_length: usize,
    orientation: [*]const u8,
    orientation_length: usize,
    weight: f32,
    letter_spacing: f32,
    word_spacing: f32,
    tab_size: f32,
    tab_size_is_length: c_int,
    fn from(t: Typography) NativeStyle {
        return .{
            .family = t.font_family.ptr,
            .family_length = t.font_family.len,
            .style = t.font_style.ptr,
            .style_length = t.font_style.len,
            .language = t.language.ptr,
            .language_length = t.language.len,
            .transform = t.text_transform.ptr,
            .transform_length = t.text_transform.len,
            .feature_settings = t.font_feature_settings.ptr,
            .feature_settings_length = t.font_feature_settings.len,
            .orientation = t.text_orientation.ptr,
            .orientation_length = t.text_orientation.len,
            .weight = t.font_weight,
            .letter_spacing = t.letter_spacing,
            .word_spacing = t.word_spacing,
            .tab_size = t.tab_size,
            .tab_size_is_length = @intFromBool(t.tab_size_is_length),
        };
    }
};
extern fn ui_text_measure_styled([*]const u8, usize, f32, *const NativeStyle, *NativeMetrics) c_int;
extern fn ui_text_raster_styled([*]const u8, usize, f32, *const NativeStyle, *c_int, *c_int) ?[*]u8;
extern fn ui_text_position_styled([*]const u8, usize, f32, f32, *const NativeStyle) c_int;
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
pub fn measureStyled(_: ?*anyopaque, text: []const u8, size: f32, typography: Typography) ui.Metrics {
    var m: NativeMetrics = undefined;
    const native = NativeStyle.from(typography);
    if (ui_text_measure_styled(text.ptr, text.len, size, &native, &m) != 0) return .{ .width = m.width, .height = m.height, .ascent = m.ascent, .descent = m.descent, .leading = m.leading };
    return (ui.Text{ .typography = typography }).measure(text, size);
}
pub fn positionStyled(_: ?*anyopaque, text: []const u8, x: f32, size: f32, typography: Typography) usize {
    const native = NativeStyle.from(typography);
    const offset: usize = @intCast(@max(0, ui_text_position_styled(text.ptr, text.len, size, x, &native)));
    // Uniscribe cluster stops and the editor's extended grapheme stops differ
    // for some emoji. Never expose a caret inside an editor grapheme.
    var previous: usize = 0;
    var next: usize = 0;
    while (next < @min(offset, text.len)) {
        previous = next;
        next = ui.text_edit.nextGrapheme(text, next);
    }
    return if (next == offset) next else previous;
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
        return self.drawStyled(text, x, y, size, color, .{});
    }
    pub fn drawStyled(self: *Cache, text: []const u8, x: f32, y: f32, size: f32, color: rl.Color, typography: Typography) !void {
        if (text.len == 0) return;
        var hash = std.hash.Wyhash.init(0);
        hash.update(text);
        hash.update(std.mem.asBytes(&size));
        inline for (.{ "font_family", "font_style", "language", "text_transform", "text_orientation" }) |field| {
            const value = @field(typography, field);
            const length = value.len;
            hash.update(std.mem.asBytes(&length));
            hash.update(value);
        }
        inline for (.{ "font_weight", "letter_spacing", "word_spacing", "tab_size", "tab_size_is_length" }) |field| hash.update(std.mem.asBytes(&@field(typography, field)));
        const key = hash.final();
        if (!self.textures.contains(key)) {
            var w: c_int = 0;
            var h: c_int = 0;
            const native = NativeStyle.from(typography);
            const pixels = ui_text_raster_styled(text.ptr, text.len, size, &native, &w, &h) orelse return error.TextRasterFailed;
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
