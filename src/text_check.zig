//! Native font contracts. Called by render-check with an active GL context.
const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui_core");
const backend = @import("text_backend.zig");
fn check(ok: bool, label: []const u8) !void {
    if (!ok) {
        std.debug.print("FAIL text: {s}\n", .{label});
        return error.TextContractMismatch;
    }
    std.debug.print("PASS text: {s}\n", .{label});
}
fn close(a: f32, b: f32) bool {
    return @abs(a - b) < 0.002;
}
fn coverage(texture: rl.Texture2D) !usize {
    const image = try rl.loadImageFromTexture(texture);
    defer rl.unloadImage(image);
    var count: usize = 0;
    for (0..@intCast(image.height)) |y| for (0..@intCast(image.width)) |x| {
        const pixel = rl.getImageColor(image, @intCast(x), @intCast(y));
        try checkPixel(pixel.r == 255 and pixel.g == 255 and pixel.b == 255);
        if (pixel.a != 0) count += 1;
    };
    return count;
}
fn checkPixel(ok: bool) !void {
    if (!ok) return error.ColoredCoverageFringe;
}
pub fn run() !void {
    const a = backend.measureStyled(null, "AV ffi, typography", 13.1, .{});
    const b = backend.measureStyled(null, "AV ffi, typography", 13.4, .{});
    try check(b.width > a.width and !close(a.width, @round(a.width)), "fractional font sizes and advances are retained");
    try check(close(b.width / a.width, 13.4 / 13.1) and close(b.ascent / a.ascent, 13.4 / 13.1), "natural metrics scale without GDI integer steps");
    const empty = backend.measureStyled(null, "", 13.1, .{});
    try check(empty.width == 0 and empty.ascent > 0 and close(empty.height, a.height), "empty runs retain the selected font line metrics");
    const raw = backend.measureStyled(null, "a b", 13.1, .{});
    const spaced = backend.measureStyled(null, "a b", 13.1, .{ .letter_spacing = 0.25, .word_spacing = 0.375 });
    try check(close(spaced.width - raw.width, 1.125), "fractional letter and word spacing share layout advances");
    const missing_family = backend.measureStyled(null, "AV ffi", 13.1, .{ .font_family = "'Definitely not a font', Segoe UI" });
    const segoe = backend.measureStyled(null, "AV ffi", 13.1, .{ .font_family = "Segoe UI" });
    try check(close(missing_family.width, segoe.width), "ordered family list skips unavailable families");
    const normal = backend.measureStyled(null, "office ffi", 24, .{ .font_family = "Calibri" });
    const no_liga = backend.measureStyled(null, "office ffi", 24, .{ .font_family = "Calibri", .font_feature_settings = "\"liga\" off" });
    const liga_glyphs = try backend.inspect("office ffi", 24, .{ .font_family = "Calibri", .font_feature_settings = "'liga' on" });
    const plain_glyphs = try backend.inspect("office ffi", 24, .{ .font_family = "Calibri", .font_feature_settings = "'liga' 0" });
    try check(liga_glyphs.glyphs < plain_glyphs.glyphs and normal.width > 0 and no_liga.width > 0, "OpenType ligature settings reach the native shaper");
    const tab = backend.measureStyled(null, "a\tb", 13.1, .{ .tab_size = 31.25, .tab_size_is_length = true });
    const single = backend.measureStyled(null, "b", 13.1, .{});
    try check(close(tab.width, 31.25 + single.width), "fractional absolute tab stops match shaping");
    const spaced_tab = backend.measureStyled(null, "a\tb", 13.1, .{ .tab_size = 31.25, .tab_size_is_length = true, .letter_spacing = 0.25, .word_spacing = 0.375 });
    try check(close(spaced_tab.width, 31.25 + single.width + 0.25), "tab stops retain their position with fractional tracking");
    const accent = backend.measureStyled(null, "e\u{301}", 13.1, .{});
    const accent_spaced = backend.measureStyled(null, "e\u{301}", 13.1, .{ .letter_spacing = 0.25 });
    try check(close(accent_spaced.width - accent.width, 0.25), "letter spacing preserves combining clusters");
    const zero_tab = backend.measureStyled(null, "a\tb", 13.1, .{ .tab_size = 0 });
    const no_tab = backend.measureStyled(null, "ab", 13.1, .{});
    try check(close(zero_tab.width, no_tab.width), "zero tab-size has zero advance");
    const author = "AV office";
    const t = ui.Text{ .styled_measure_fn = backend.measureStyled, .styled_position_fn = backend.positionStyled, .styled_caret_fn = backend.caretStyled };
    const caret = t.caret(author, 1, 24);
    try check(@abs(caret - t.width("A", 24)) > 0.01, "caret uses the full kerned run rather than a separately shaped prefix");
    try check(t.position(author, caret + 0.01, 24).? == 1, "fractional caret and hit testing agree within a shaped run");
    const transformed = ui.Text{ .styled_measure_fn = backend.measureStyled, .styled_position_fn = backend.positionStyled, .styled_caret_fn = backend.caretStyled, .typography = .{ .text_transform = "uppercase" } };
    const expansion = "straße";
    try check(close(transformed.width(expansion, 20), t.width("STRASSE", 20)), "uppercase sharp s expands to the CSS display sequence");
    const expansion_caret = transformed.caret(expansion, 6, 20);
    try check(transformed.position(expansion, expansion_caret + 0.01, 20).? == 6, "case expansion maps display carets back to author UTF-8");
    const rtl = "مرحبا";
    const rtl_start = t.caret(rtl, 0, 20);
    const rtl_end = t.caret(rtl, rtl.len, 20);
    try check(rtl_start > rtl_end and t.position(rtl, rtl_start - 0.01, 20).? == 0, "RTL caret direction and hit testing use the same bidi layout");
    const bidi_selection = try backend.selectionStyled(std.heap.page_allocator, "abc مرحبا xyz", 1, 8, 20, .{});
    defer std.heap.page_allocator.free(bidi_selection);
    try check(bidi_selection.len >= 2, "mixed bidi selection uses the native visual range rectangles");
    var cache = backend.Cache.init(std.heap.page_allocator);
    defer cache.deinit();
    rl.beginDrawing();
    defer rl.endDrawing();
    try cache.drawStyled("AV ffi", 0.25, 0.5, 13.1, .white, .{});
    var first = cache.textures.valueIterator();
    const first_texture = first.next().?.texture;
    const first_width = first_texture.width;
    try check(try coverage(first_texture) > 10, "fractional-origin raster contains neutral white coverage");
    try cache.drawStyled("AV ffi", 1.25, 2.5, 13.1, .red, .{});
    try check(cache.raster_runs == 1, "integer translations and paint color reuse glyph coverage");
    try cache.drawStyled("AV ffi", 1.5, 2.5, 13.1, .white, .{});
    try check(cache.raster_runs == 2, "fractional device origin invalidates raster coverage");
    const logical = backend.measureCached(&cache, "AV ffi", 13.1, .{});
    for ([_]f32{ 1.25, 1.5, 2 }) |scale| {
        _ = cache.setScale(scale);
        try check(cache.textures.count() == 0, "DPI change evicts old device rasters");
        try cache.drawStyled("AV ffi", 0.25, 0.5, 13.1, .white, .{});
        var textures = cache.textures.valueIterator();
        const texture = textures.next().?.texture;
        try check(texture.width > first_width and try coverage(texture) > 10, "125/150/200 percent DPI produces larger native coverage");
        const measured = backend.measureCached(&cache, "AV ffi", 13.1, .{});
        try check(close(measured.width, logical.width) and cache.measurement_runs == 1, "DPI changes preserve logical layout and its metric cache");
    }
    cache.invalidateFonts();
    try check(cache.textures.count() == 0 and cache.metrics.count() == 0, "font collection change invalidates layouts metrics and coverage");
    _ = cache.setScale(1);
    const overhang_style = ui.text.Typography{ .font_family = "Times New Roman", .font_style = "italic" };
    try cache.drawStyled("j", 0, 0, 32, .white, overhang_style);
    var overhangs = cache.textures.valueIterator();
    try check(overhangs.next().?.left < 0, "italic negative ink bearing is preserved outside the advance box");
    cache.invalidateFonts();
    try cache.drawStyled("sideways", 0, 0, 20, .white, .{ .text_orientation = "sideways" });
    var rotated = cache.textures.valueIterator();
    const rotated_texture = rotated.next().?.texture;
    try check(rotated_texture.height > rotated_texture.width, "explicit sideways orientation retains rotated glyph coverage");
    cache.invalidateFonts();
    const samples = [_][]const u8{ "Latin AV ffi", "नमस्ते दुनिया", "مرحبا بالعالم", "שלום עולם", "中文 日本語 한글", "e\u{301} 👩‍💻 🏳️‍🌈" };
    for (samples) |sample| {
        const inspection = try backend.inspect(sample, 19.25, .{});
        std.debug.print("Native font coverage: {s}: {d} glyphs, {d} missing, {d} runs\n", .{ sample, inspection.glyphs, inspection.missing, inspection.runs });
        try check(inspection.glyphs > 0 and inspection.missing == 0, "installed multilingual fallback supplies actual glyphs");
        try cache.drawStyled(sample, 0, 0, 19.25, .white, .{});
        const m = backend.measureStyled(null, sample, 19.25, .{});
        try check(m.width > 0 and m.ascent > 0, "multilingual metrics retain nonempty shaped coverage");
    }
    try check(backend.positionStyled(null, "👩‍💻", 5, 20, .{}) == 0, "editor never exposes an interior emoji grapheme caret");
}
