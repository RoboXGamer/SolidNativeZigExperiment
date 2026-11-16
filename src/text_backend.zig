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
extern fn ui_text_raster_styled([*]const u8, usize, f32, *const NativeStyle, f32, f32, f32, *c_int, *c_int, *c_int, *c_int) ?[*]u8;
extern fn ui_text_position_styled([*]const u8, usize, f32, f32, *const NativeStyle) c_int;
extern fn ui_text_caret_styled([*]const u8, usize, f32, usize, *const NativeStyle) f32;
extern fn ui_text_invalidate_fonts() void;
extern fn ui_text_inspect_styled([*]const u8, usize, f32, *const NativeStyle, *u32, *u32, *u32) c_int;
pub const Inspection = struct { glyphs: u32, missing: u32, runs: u32 };
pub fn inspect(text: []const u8, size: f32, typography: Typography) !Inspection {
    const native = NativeStyle.from(typography);
    var result: Inspection = undefined;
    if (ui_text_inspect_styled(text.ptr, text.len, size, &native, &result.glyphs, &result.missing, &result.runs) == 0) return error.TextInspectionFailed;
    return result;
}
extern fn ui_text_free(*anyopaque) void;
pub extern fn ui_text_ime_position(?*anyopaque, f32, f32) void;
extern fn ui_text_selection_styled([*]const u8, usize, f32, usize, usize, *const NativeStyle, ?[*]rl.Rectangle, u32) c_int;
pub fn selectionStyled(a: std.mem.Allocator, text: []const u8, start: usize, end: usize, size: f32, typography: Typography) ![]rl.Rectangle {
    const native = NativeStyle.from(typography);
    const count = ui_text_selection_styled(text.ptr, text.len, size, start, end, &native, null, 0);
    if (count < 0) return error.TextSelectionFailed;
    const rects = try a.alloc(rl.Rectangle, @intCast(count));
    errdefer a.free(rects);
    if (ui_text_selection_styled(text.ptr, text.len, size, start, end, &native, rects.ptr, @intCast(count)) != count) return error.TextSelectionFailed;
    return rects;
}
pub extern fn ui_text_initialize_dpi() void;
pub extern fn ui_text_watch_fonts(?*anyopaque) void;
pub extern fn ui_text_unwatch_fonts() void;
extern fn ui_text_fonts_changed() c_int;
pub const initializeDpi = ui_text_initialize_dpi;
pub const watchFonts = ui_text_watch_fonts;
pub const unwatchFonts = ui_text_unwatch_fonts;
pub fn fontsChanged() bool {
    return ui_text_fonts_changed() != 0;
}
pub fn measureStyled(_: ?*anyopaque, text: []const u8, size: f32, typography: Typography) ui.Metrics {
    var m: NativeMetrics = undefined;
    const native = NativeStyle.from(typography);
    if (ui_text_measure_styled(text.ptr, text.len, size, &native, &m) != 0) return .{ .width = m.width, .height = m.height, .ascent = m.ascent, .descent = m.descent, .leading = m.leading };
    return (ui.Text{ .typography = typography }).measure(text, size);
}
fn runKey(text: []const u8, size: f32, typography: Typography) u64 {
    var hash = std.hash.Wyhash.init(0);
    const text_length = text.len;
    hash.update(std.mem.asBytes(&text_length));
    hash.update(text);
    hash.update(std.mem.asBytes(&size));
    inline for (.{ "font_family", "font_style", "language", "text_transform", "text_orientation", "font_feature_settings" }) |field| {
        const value = @field(typography, field);
        const length = value.len;
        hash.update(std.mem.asBytes(&length));
        hash.update(value);
    }
    inline for (.{ "font_weight", "letter_spacing", "word_spacing", "tab_size", "tab_size_is_length" }) |field| hash.update(std.mem.asBytes(&@field(typography, field)));
    return hash.final();
}
pub fn measureCached(ctx: ?*anyopaque, text: []const u8, size: f32, typography: Typography) ui.Metrics {
    const cache: *Cache = @ptrCast(@alignCast(ctx orelse return measureStyled(null, text, size, typography)));
    const key = runKey(text, size, typography);
    if (cache.metrics.get(key)) |metrics| return metrics;
    const metrics = measureStyled(null, text, size, typography);
    cache.measurement_runs += 1;
    if (cache.metrics.count() >= 4096) cache.metrics.clearRetainingCapacity();
    cache.metrics.put(key, metrics) catch {};
    return metrics;
}
pub fn positionStyled(_: ?*anyopaque, text: []const u8, x: f32, size: f32, typography: Typography) usize {
    const native = NativeStyle.from(typography);
    const offset: usize = @intCast(@max(0, ui_text_position_styled(text.ptr, text.len, size, x, &native)));
    // DirectWrite cluster stops and the editor's extended grapheme stops differ
    // for some emoji. Never expose a caret inside an editor grapheme.
    var previous: usize = 0;
    var next: usize = 0;
    while (next < @min(offset, text.len)) {
        previous = next;
        next = ui.text_edit.nextGrapheme(text, next);
    }
    return if (next == offset) next else previous;
}
pub fn caretStyled(_: ?*anyopaque, text: []const u8, offset: usize, size: f32, typography: Typography) f32 {
    const native = NativeStyle.from(typography);
    return ui_text_caret_styled(text.ptr, text.len, size, offset, &native);
}
pub const GlyphTexture = struct { texture: rl.Texture2D, left: f32, top: f32 };
pub const Cache = struct {
    allocator: std.mem.Allocator,
    textures: std.AutoHashMap(u64, GlyphTexture),
    metrics: std.AutoHashMap(u64, ui.Metrics),
    measurement_runs: usize = 0,
    raster_runs: usize = 0,
    scale: f32 = 1,
    texture_bytes: usize = 0,
    pub fn init(a: std.mem.Allocator) Cache {
        return .{ .allocator = a, .textures = std.AutoHashMap(u64, GlyphTexture).init(a), .metrics = std.AutoHashMap(u64, ui.Metrics).init(a) };
    }
    fn clearTextures(self: *Cache) void {
        // A cache eviction can happen mid-frame; submit queued draws before
        // deleting textures still referenced by the current rlgl batch.
        rl.gl.rlDrawRenderBatchActive();
        var it = self.textures.valueIterator();
        while (it.next()) |t| rl.unloadTexture(t.texture);
        self.textures.clearRetainingCapacity();
        self.texture_bytes = 0;
    }
    pub fn setScale(self: *Cache, scale: f32) bool {
        const next = if (std.math.isFinite(scale) and scale > 0) scale else 1;
        if (next == self.scale) return false;
        self.clearTextures();
        self.scale = next;
        return true;
    }
    pub fn invalidateFonts(self: *Cache) void {
        self.clearTextures();
        self.metrics.clearRetainingCapacity();
        ui_text_invalidate_fonts();
    }
    pub fn deinit(self: *Cache) void {
        self.clearTextures();
        self.textures.deinit();
        self.metrics.deinit();
    }
    pub fn drawStyled(self: *Cache, text: []const u8, x: f32, y: f32, size: f32, color: rl.Color, typography: Typography) !void {
        if (text.len == 0) return;
        // Fractional device-space origins are raster dependencies, not layout
        // dependencies. Bake coverage at the phase, then align the quad to pixels.
        const matrix = rl.gl.rlGetMatrixTransform();
        const world_x = (matrix.m0 * x + matrix.m4 * y + matrix.m12) * self.scale;
        const world_y = (matrix.m1 * x + matrix.m5 * y + matrix.m13) * self.scale;
        const axis_aligned = @abs(matrix.m1) < 0.0001 and @abs(matrix.m4) < 0.0001 and matrix.m0 > 0 and @abs(matrix.m0 - matrix.m5) < 0.0001;
        const raster_scale = self.scale * (if (axis_aligned) matrix.m0 else 1);
        const phase_x = if (axis_aligned) @mod(world_x, 1) else 0;
        const phase_y = if (axis_aligned) @mod(world_y, 1) else 0;
        var hash = std.hash.Wyhash.init(runKey(text, size, typography));
        hash.update(std.mem.asBytes(&raster_scale));
        hash.update(std.mem.asBytes(&phase_x));
        hash.update(std.mem.asBytes(&phase_y));
        const key = hash.final();
        if (!self.textures.contains(key)) {
            var w: c_int = 0;
            var h: c_int = 0;
            var left: c_int = 0;
            var top: c_int = 0;
            const native = NativeStyle.from(typography);
            const pixels = ui_text_raster_styled(text.ptr, text.len, size, &native, raster_scale, phase_x, phase_y, &w, &h, &left, &top) orelse return error.TextRasterFailed;
            self.raster_runs += 1;
            defer ui_text_free(@ptrCast(pixels));
            const image = rl.Image{ .data = @ptrCast(pixels), .width = w, .height = h, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
            const texture = try rl.loadTextureFromImage(image);
            errdefer rl.unloadTexture(texture);
            rl.setTextureFilter(texture, .bilinear);
            // Bound cache growth under rapidly changing counters / HMR.
            const bytes = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;
            if (self.textures.count() >= 512 or self.texture_bytes + bytes > 32 * 1024 * 1024) self.clearTextures();
            try self.textures.put(key, .{ .texture = texture, .left = @floatFromInt(left), .top = @floatFromInt(top) });
            self.texture_bytes += bytes;
        }
        const glyph = self.textures.get(key).?;
        const texture = glyph.texture;
        rl.drawTexturePro(texture, .{ .x = 0, .y = 0, .width = @floatFromInt(texture.width), .height = @floatFromInt(texture.height) }, .{ .x = x + (glyph.left - phase_x) / raster_scale, .y = y + (glyph.top - phase_y) / raster_scale, .width = @as(f32, @floatFromInt(texture.width)) / raster_scale, .height = @as(f32, @floatFromInt(texture.height)) / raster_scale }, .{ .x = 0, .y = 0 }, 0, color);
    }
};
