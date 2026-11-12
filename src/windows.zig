const rl = @import("raylib");
const std = @import("std");
const ui = @import("ui_core");
const bridge = @import("solid_bridge");
extern fn ui_watch_start() c_int;
extern fn ui_watch_changed() c_int;
extern fn ui_watch_stop() void;
extern fn ui_wake_start() c_int;
extern fn ui_wake_schedule(seconds: f64) void;
extern fn ui_wake_stop() void;
extern fn ui_cursor_update([*]const u8, usize, c_int, c_int) void;
extern fn ui_cursor_shutdown() void;
extern fn getenv([*:0]const u8) ?[*:0]const u8;

const source = @embedFile("ui-bundle.js");
const window_width = 1280;
const window_height = 720;
const background_color = rl.Color.init(51, 51, 51, 255);

fn color(value: []const u8, fallback: rl.Color) rl.Color {
    return colorWithOpacity(value, fallback, 1.0);
}

fn colorWithOpacity(value: []const u8, fallback: rl.Color, opacity: f32) rl.Color {
    var c = fallback;
    if (ui.gradient.parseColor(value)) |rgba| c = rl.Color.init(rgba[0], rgba[1], rgba[2], rgba[3]);
    c.a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * std.math.clamp(opacity, 0, 1));
    return c;
}

const text_backend = @import("text_backend.zig");
const DrawContext = struct { focused: ?u32, editor: *ui.TextEdit, scroll_offsets: *std.AutoHashMap(u32, ui.ScrollOffset), text_cache: *text_backend.Cache };

fn drawDecorLine(start_x: f32, end_x: f32, y: f32, thickness: f32, style: []const u8, c: rl.Color) void {
    if (end_x <= start_x) return;
    if (std.mem.eql(u8, style, "double")) {
        const off = @max(1.0, thickness);
        rl.drawLineEx(.{ .x = start_x, .y = y - off }, .{ .x = end_x, .y = y - off }, thickness, c);
        rl.drawLineEx(.{ .x = start_x, .y = y + off }, .{ .x = end_x, .y = y + off }, thickness, c);
    } else if (std.mem.eql(u8, style, "dashed")) {
        const dash_len = @max(3.0, thickness * 3.0);
        var cur_x = start_x;
        var draw_dash = true;
        while (cur_x < end_x) {
            const next_x = @min(end_x, cur_x + dash_len);
            if (draw_dash) {
                rl.drawLineEx(.{ .x = cur_x, .y = y }, .{ .x = next_x, .y = y }, thickness, c);
            }
            cur_x = next_x;
            draw_dash = !draw_dash;
        }
    } else if (std.mem.eql(u8, style, "dotted")) {
        const r = @max(0.5, thickness / 2.0);
        const step = @max(2.0, thickness * 2.0);
        var cur_x = start_x + r;
        while (cur_x <= end_x) {
            rl.drawCircleV(.{ .x = cur_x, .y = y }, r, c);
            cur_x += step;
        }
    } else if (std.mem.eql(u8, style, "wavy")) {
        const wave_len = @max(4.0, thickness * 4.0);
        const amp = @max(1.0, thickness * 1.2);
        var px = start_x;
        while (px < end_x) {
            const nx = @min(end_x, px + 1.0);
            const py1 = y + @sin((px - start_x) / wave_len * 2.0 * std.math.pi) * amp;
            const py2 = y + @sin((nx - start_x) / wave_len * 2.0 * std.math.pi) * amp;
            rl.drawLineEx(.{ .x = px, .y = py1 }, .{ .x = nx, .y = py2 }, thickness, c);
            px = nx;
        }
    } else {
        rl.drawLineEx(.{ .x = start_x, .y = y }, .{ .x = end_x, .y = y }, thickness, c);
    }
}

fn drawTextDecoration(sline: ui.text.ShapedLine, line_x: f32, line_y: f32, font_sz: f32, typo: ui.text.Typography, text_measurer: ui.Text, decor_color: rl.Color) void {
    if (typo.text_decoration_line.len == 0 or std.mem.eql(u8, typo.text_decoration_line, "none")) return;
    var thickness: f32 = @max(1.0, @round(font_sz / 14.0));
    if (typo.text_decoration_thickness > 0) {
        thickness = typo.text_decoration_thickness;
    }
    const style = if ((std.mem.indexOf(u8, typo.text_decoration_line, "spelling-error") != null or std.mem.indexOf(u8, typo.text_decoration_line, "grammar-error") != null) and std.mem.eql(u8, typo.text_decoration_style, "solid")) "wavy" else if (typo.text_decoration_style.len > 0) typo.text_decoration_style else "solid";
    const skip_ink = std.mem.eql(u8, typo.text_decoration_skip_ink, "auto");

    const has_under = std.mem.indexOf(u8, typo.text_decoration_line, "underline") != null or std.mem.indexOf(u8, typo.text_decoration_line, "spelling-error") != null or std.mem.indexOf(u8, typo.text_decoration_line, "grammar-error") != null;
    const has_over = std.mem.indexOf(u8, typo.text_decoration_line, "overline") != null;
    const has_through = std.mem.indexOf(u8, typo.text_decoration_line, "line-through") != null;

    if (has_over) {
        drawDecorLine(line_x, line_x + sline.width, line_y, thickness, style, decor_color);
    }
    if (has_through) {
        const through_y = line_y + sline.ascent * 0.6;
        drawDecorLine(line_x, line_x + sline.width, through_y, thickness, style, decor_color);
    }
    if (has_under) {
        const under_y = line_y + sline.ascent + (if (std.mem.indexOf(u8, typo.text_underline_position, "under") != null) @max(1.0, font_sz * 0.2) else thickness + 1.0) + typo.text_underline_offset;
        if (!skip_ink) {
            drawDecorLine(line_x, line_x + sline.width, under_y, thickness, style, decor_color);
        } else {
            var seg_start = line_x;
            var offset: usize = 0;
            while (offset < sline.text.len) {
                const next = ui.text_edit.nextGrapheme(sline.text, offset);
                const char_slice = sline.text[offset..next];
                const char_w = text_measurer.width(char_slice, font_sz);
                const char_x = line_x + text_measurer.width(sline.text[0..offset], font_sz);
                if (char_slice.len > 0 and ui.text.hasDescender(char_slice[0])) {
                    if (char_x > seg_start) drawDecorLine(seg_start, char_x, under_y, thickness, style, decor_color);
                    seg_start = char_x + char_w;
                }
                offset = next;
            }
            if (line_x + sline.width > seg_start) {
                drawDecorLine(seg_start, line_x + sline.width, under_y, thickness, style, decor_color);
            }
        }
    }
}

fn drawTextEmphasis(ctx: *DrawContext, sline: ui.text.ShapedLine, line_x: f32, line_y: f32, font_sz: f32, typo: ui.text.Typography, text_measurer: ui.Text, emphasis_color: rl.Color) !void {
    if (typo.text_emphasis_style.len == 0 or std.mem.eql(u8, typo.text_emphasis_style, "none")) return;
    const mark = ui.text.emphasisMark(typo.text_emphasis_style);
    if (mark.len == 0) return;
    const is_under = std.mem.indexOf(u8, typo.text_emphasis_position, "under") != null;
    const mark_sz = font_sz * 0.5;
    const mark_y = if (is_under) line_y + sline.ascent + font_sz * 0.2 else line_y - font_sz * 0.45;
    const mark_w = text_measurer.width(mark, mark_sz);

    var offset: usize = 0;
    while (offset < sline.text.len) {
        const next = ui.text_edit.nextGrapheme(sline.text, offset);
        const char_slice = sline.text[offset..next];
        const char_w = text_measurer.width(char_slice, font_sz);
        const char_x = line_x + text_measurer.width(sline.text[0..offset], font_sz);
        if (char_slice.len > 0 and char_slice[0] != ' ' and char_slice[0] != '\t' and char_slice[0] != '\r' and char_slice[0] != '\n') {
            const mark_x = char_x + (char_w - mark_w) / 2.0;
            try ctx.text_cache.drawStyled(mark, mark_x, mark_y, mark_sz, emphasis_color, .{ .font_family = typo.font_family });
        }
        offset = next;
    }
}

fn drawItem(context: *anyopaque, scene: *ui.Scene, item: ui.Item, allocator: std.mem.Allocator) !void {
    const ctx: *DrawContext = @ptrCast(@alignCast(context));
    const focused = ctx.focused;
    const editor = ctx.editor;
    const scroll_offsets = ctx.scroll_offsets;
    const n = item.node;
    const text = n.textContext(scene.text);
    if (std.mem.eql(u8, n.type, "__layout_root")) return;
    const b = item.bounds;
    const rect = rl.Rectangle{ .x = b.x, .y = b.y, .width = b.width, .height = b.height };

    const op: f32 = 1;

    const font_size_int: i32 = @intFromFloat(@max(1.0, @round(n.fontSize())));
    if (std.mem.eql(u8, n.type, "text") and n.text.len > 0) {
        const content = n.contentBox(b);
        const line_h = if (n.style.lineHeight) |lh| (if (lh > 0) lh else text.lineHeight(n.fontSize())) else text.lineHeight(n.fontSize());
        const available = @max(0, @min(content.width, scene.clipFor(item).right() - content.x));
        const lines = n.shapeText(scene.text, allocator, available) catch &.{};
        for (lines, 0..) |sline, line_idx| {
            const line_x = content.x + sline.offset_x;
            const line_y = content.y + @as(f32, @floatFromInt(line_idx)) * line_h + sline.offset_y;

            const base_color = colorWithOpacity(n.style.color, .white, op);
            const fill_color = if (n.style.textFillColor.len > 0 and !std.mem.eql(u8, n.style.textFillColor, "none"))
                colorWithOpacity(n.style.textFillColor, .white, op)
            else
                base_color;

            // 1. Text Shadows (Issue #254)
            if (n.style.textShadow.len > 0 and !std.mem.eql(u8, n.style.textShadow, "none")) {
                const default_shadow_color = ui.paint.Color{ base_color.r, base_color.g, base_color.b, base_color.a };
                if (ui.paint.textShadows(allocator, n.style.textShadow, default_shadow_color)) |tshadows| {
                    defer allocator.free(tshadows);
                    for (tshadows) |s| {
                        const sc = rl.Color.init(s.color[0], s.color[1], s.color[2], @intFromFloat(@as(f32, @floatFromInt(s.color[3])) * op));
                        if (s.blur > 0) {
                            const bstep = s.blur * 0.5;
                            const sub_sc = rl.Color.init(sc.r, sc.g, sc.b, sc.a / 4);
                            try ctx.text_cache.drawStyled(sline.text, line_x + s.x - bstep, line_y + s.y, n.fontSize(), sub_sc, text.typography);
                            try ctx.text_cache.drawStyled(sline.text, line_x + s.x + bstep, line_y + s.y, n.fontSize(), sub_sc, text.typography);
                            try ctx.text_cache.drawStyled(sline.text, line_x + s.x, line_y + s.y - bstep, n.fontSize(), sub_sc, text.typography);
                            try ctx.text_cache.drawStyled(sline.text, line_x + s.x, line_y + s.y + bstep, n.fontSize(), sub_sc, text.typography);
                        } else {
                            try ctx.text_cache.drawStyled(sline.text, line_x + s.x, line_y + s.y, n.fontSize(), sc, text.typography);
                        }
                    }
                } else |_| {}
            }

            // 2. Text Stroke (Issue #255)
            if (n.style.textStrokeWidth > 0) {
                const stroke_color = if (n.style.textStrokeColor.len > 0)
                    colorWithOpacity(n.style.textStrokeColor, .white, op)
                else
                    base_color;
                const sw = n.style.textStrokeWidth;
                inline for (.{ .{ -1.0, 0.0 }, .{ 1.0, 0.0 }, .{ 0.0, -1.0 }, .{ 0.0, 1.0 }, .{ -0.7, -0.7 }, .{ 0.7, -0.7 }, .{ -0.7, 0.7 }, .{ 0.7, 0.7 } }) |offset| {
                    try ctx.text_cache.drawStyled(sline.text, line_x + sw * offset[0], line_y + sw * offset[1], n.fontSize(), stroke_color, text.typography);
                }
            }

            // 3. Text Fill (Issue #255)
            if (fill_color.a > 0) {
                try ctx.text_cache.drawStyled(sline.text, line_x, line_y, n.fontSize(), fill_color, text.typography);
            }

            const decor_col = colorWithOpacity(if (n.style.textDecorationColor.len > 0) n.style.textDecorationColor else if (std.mem.indexOf(u8, n.style.textDecorationLine, "spelling-error") != null) "red" else if (std.mem.indexOf(u8, n.style.textDecorationLine, "grammar-error") != null) "green" else n.style.color, .white, op);
            drawTextDecoration(sline, line_x, line_y, n.fontSize(), text.typography, text, decor_col);
            // 4. Text Underline (Issues #257, #258)
            const has_underline = std.mem.indexOf(u8, n.style.textDecoration, "underline") != null or
                std.mem.indexOf(u8, n.style.textDecorationLine, "underline") != null or
                n.style.textUnderlineOffset != null or
                (!std.mem.eql(u8, n.style.textUnderlinePosition, "auto") and !std.mem.eql(u8, n.style.textUnderlinePosition, "none"));

            if (has_underline and !std.mem.eql(u8, n.style.writingMode, "horizontal-tb")) {
                const u_color = if (n.style.textDecorationColor.len > 0)
                    colorWithOpacity(n.style.textDecorationColor, .white, op)
                else
                    fill_color;
                const u_thickness = n.style.textDecorationThickness orelse @max(1.0, @round(n.fontSize() * 0.06));
                const under_pos = n.style.textUnderlinePosition;
                const is_under = std.mem.indexOf(u8, under_pos, "under") != null;
                const base_y = if (is_under)
                    line_y + sline.ascent + text.descent(n.fontSize()) + 1.0
                else
                    line_y + sline.ascent + @max(1.0, @round(n.fontSize() * 0.1));
                const underline_y = base_y + (n.style.textUnderlineOffset orelse 0);

                const is_vertical = !std.mem.eql(u8, n.style.writingMode, "horizontal-tb");
                if (is_vertical) {
                    const is_left = std.mem.indexOf(u8, under_pos, "left") != null;
                    const u_x = if (is_left) line_x - (n.style.textUnderlineOffset orelse 0) - u_thickness else line_x + sline.width + (n.style.textUnderlineOffset orelse 0);
                    rl.drawRectangleRec(.{ .x = u_x, .y = line_y, .width = u_thickness, .height = sline.height }, u_color);
                } else {
                    rl.drawRectangleRec(.{ .x = line_x, .y = underline_y, .width = sline.width, .height = u_thickness }, u_color);
                }
            }

            const emph_col = colorWithOpacity(if (text.typography.text_emphasis_color.len > 0) text.typography.text_emphasis_color else n.style.color, .white, op);
            try drawTextEmphasis(ctx, sline, line_x, line_y, n.fontSize(), text.typography, text, emph_col);
        }
    }
    const is_vertical = !std.mem.eql(u8, n.style.writingMode, "horizontal-tb");
    if (std.mem.eql(u8, n.type, "select")) {
        const display_text = if (n.text.len > 0) n.text else n.value;
        const content = n.contentBox(b);
        if (display_text.len > 0) {
            const select_color = if (n.style.textFillColor.len > 0 and !std.mem.eql(u8, n.style.textFillColor, "none"))
                colorWithOpacity(n.style.textFillColor, .white, op)
            else
                colorWithOpacity(n.style.color, .white, op);
            try ctx.text_cache.drawStyled(display_text, content.x, content.y, n.fontSize(), select_color, text.typography);
        }
        if (is_vertical) {
            const arrow_y = b.y + b.height - 20;
            if (arrow_y > content.y) {
                try ctx.text_cache.drawStyled("v", content.x, arrow_y, n.fontSize(), colorWithOpacity(n.style.color, .light_gray, op), text.typography);
            }
        } else {
            const arrow_x = b.x + b.width - 20;
            if (arrow_x > content.x) {
                try ctx.text_cache.drawStyled("v", arrow_x, content.y, n.fontSize(), colorWithOpacity(n.style.color, .light_gray, op), text.typography);
            }
        }
    }
    if (std.mem.eql(u8, n.type, "input")) {
        const content = n.contentBox(b);
        var text_x = content.x;
        var text_y = content.y;
        if (focused == n.id) {
            editor.clamp(n.value);
            const caret = text.width(n.value[0..editor.cursor], n.fontSize());
            if (is_vertical) {
                text_y -= @max(0, caret - @max(0, content.height - 4));
                const selected = editor.selection();
                const start = text.width(n.value[0..selected.start], n.fontSize());
                const end = text.width(n.value[0..selected.end], n.fontSize());
                if (selected.start != selected.end) {
                    rl.drawRectangleRec(.{ .x = text_x, .y = text_y + start, .width = @floatFromInt(font_size_int), .height = end - start }, .blue);
                } else {
                    rl.drawLineEx(.{ .x = text_x, .y = text_y + caret }, .{ .x = text_x + @as(f32, @floatFromInt(font_size_int)), .y = text_y + caret }, 1, .white);
                }
            } else {
                text_x -= @max(0, caret - @max(0, content.width - 4));
                const selected = editor.selection();
                const start = text.width(n.value[0..selected.start], n.fontSize());
                const end = text.width(n.value[0..selected.end], n.fontSize());
                if (selected.start != selected.end) {
                    rl.drawRectangleRec(.{ .x = text_x + start, .y = text_y, .width = end - start, .height = @floatFromInt(font_size_int) }, .blue);
                } else {
                    rl.drawLineEx(.{ .x = text_x + caret, .y = text_y }, .{ .x = text_x + caret, .y = text_y + @as(f32, @floatFromInt(font_size_int)) }, 1, .white);
                }
            }
        }
        const input_color = if (n.style.textFillColor.len > 0 and !std.mem.eql(u8, n.style.textFillColor, "none"))
            colorWithOpacity(n.style.textFillColor, .white, op)
        else
            colorWithOpacity(n.style.color, .white, op);
        try ctx.text_cache.drawStyled(n.value, text_x, text_y, n.fontSize(), input_color, text.typography);
        if (focused == n.id) {
            if (is_vertical) {
                text_backend.ui_text_ime_position(rl.getWindowHandle(), @intFromFloat(text_x + @as(f32, @floatFromInt(font_size_int))), @intFromFloat(text_y + text.width(n.value[0..editor.cursor], n.fontSize())));
            } else {
                text_backend.ui_text_ime_position(rl.getWindowHandle(), @intFromFloat(text_x + text.width(n.value[0..editor.cursor], n.fontSize())), @intFromFloat(text_y + text.lineHeight(n.fontSize())));
            }
        }
    }
    // Scrollbar rendering
    if (n.isScrollContainer() and !std.mem.eql(u8, n.style.scrollbarWidth, "none")) {
        const extent = scene.scrollExtent(n.id);
        const track_thickness: f32 = if (std.mem.eql(u8, n.style.scrollbarWidth, "thin")) 4 else 8;
        const default_track_c = rl.Color.init(0, 0, 0, 40);
        const default_thumb_c = rl.Color.init(255, 255, 255, 100);
        const track_color = if (n.style.scrollbarTrackColor.len > 0)
            colorWithOpacity(n.style.scrollbarTrackColor, default_track_c, op)
        else
            default_track_c;
        const thumb_color = if (n.style.scrollbarThumbColor.len > 0)
            colorWithOpacity(n.style.scrollbarThumbColor, default_thumb_c, op)
        else
            default_thumb_c;

        if (extent.max_scroll_y > 0) {
            const track_w = track_thickness;
            const track_h = rect.height;
            const track_x = rect.x + rect.width - track_w;
            const track_y = rect.y;
            rl.drawRectangleRec(.{ .x = track_x, .y = track_y, .width = track_w, .height = track_h }, track_color);
            const thumb_h = @max(16, track_h * (rect.height / extent.total_height));
            const cur_offset = if (scroll_offsets.get(n.id)) |so| so.y else 0;
            const thumb_y = track_y + (cur_offset / extent.max_scroll_y) * (track_h - thumb_h);
            rl.drawRectangleRec(.{ .x = track_x, .y = thumb_y, .width = track_w, .height = thumb_h }, thumb_color);
        }
        if (extent.max_scroll_x > 0) {
            const track_h: f32 = if (std.mem.eql(u8, n.style.scrollbarWidth, "thin")) 4 else 8;
            const track_w = rect.width;
            const track_x = rect.x;
            const track_y = rect.y + rect.height - track_h;
            rl.drawRectangleRec(.{ .x = track_x, .y = track_y, .width = track_w, .height = track_h }, track_color);
            const thumb_w = @max(16, track_w * (rect.width / extent.total_width));
            const cur_offset = if (scroll_offsets.get(n.id)) |so| so.x else 0;
            const thumb_x = track_x + (cur_offset / extent.max_scroll_x) * (track_w - thumb_w);
            rl.drawRectangleRec(.{ .x = thumb_x, .y = track_y, .width = thumb_w, .height = track_h }, thumb_color);
        }
    }
    if (focused == n.id) rl.drawRectangleLinesEx(rect, 2, .sky_blue);
}

fn pressed(key: rl.KeyboardKey) bool {
    return rl.isKeyPressed(key) or rl.isKeyPressedRepeat(key);
}

fn keyboard(runtime: *bridge.Runtime, scene: *ui.Scene, focused: ?u32, editor: *ui.TextEdit, allocator: std.mem.Allocator) !void {
    const item = scene.find(focused orelse return) orelse return;
    if (std.mem.eql(u8, item.node.type, "select")) {
        if (pressed(.up)) {
            try runtime.key(item.node.id, "ArrowUp");
        } else if (pressed(.down)) {
            try runtime.key(item.node.id, "ArrowDown");
        } else if (rl.isKeyPressed(.space)) {
            try runtime.key(item.node.id, "Space");
        } else if (rl.isKeyPressed(.enter)) {
            try runtime.key(item.node.id, "Enter");
        } else if (rl.isKeyPressed(.escape)) {
            try runtime.key(item.node.id, "Escape");
        }
        return;
    }
    if (!std.mem.eql(u8, item.node.type, "input")) return;
    const a = allocator;
    var value = item.node.value;
    editor.clamp(value);
    const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    const control = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
    var changed = false;
    if (pressed(.left)) editor.left(value, shift);
    if (pressed(.right)) editor.right(value, shift);
    if (pressed(.home)) editor.move(0, shift);
    if (pressed(.end)) editor.move(value.len, shift);
    if (control and rl.isKeyPressed(.a)) {
        editor.anchor = 0;
        editor.cursor = value.len;
    }
    if (control and (rl.isKeyPressed(.c) or rl.isKeyPressed(.x))) {
        const selected = editor.selection();
        if (selected.start != selected.end) {
            rl.setClipboardText(try a.dupeSentinel(u8, value[selected.start..selected.end], 0));
            if (rl.isKeyPressed(.x)) {
                value = try editor.replace(a, value, "");
                changed = true;
            }
        }
    }
    if (control and rl.isKeyPressed(.v)) {
        const pasted = rl.getClipboardText();
        // A single-line input accepts pasted text up to its first line break.
        const end = std.mem.indexOfAny(u8, pasted, "\r\n") orelse pasted.len;
        value = try editor.replace(a, value, pasted[0..end]);
        changed = true;
    }
    if (pressed(.backspace)) {
        value = try editor.backspace(a, value);
        changed = true;
    }
    if (pressed(.delete)) {
        value = try editor.delete(a, value);
        changed = true;
    }
    var codepoint = rl.getCharPressed();
    while (codepoint > 0) : (codepoint = rl.getCharPressed()) {
        if (control or codepoint < 32) continue;
        var bytes: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &bytes) catch continue;
        value = try editor.replace(a, value, bytes[0..len]);
        changed = true;
    }
    if (changed) try runtime.input(item.node.id, try a.dupeSentinel(u8, value, 0));
}

fn synchronize(runtime: *bridge.Runtime, tree: *ui.Tree) !bool {
    const json = try runtime.changes();
    defer runtime.freeChanges(json);
    const changed = try tree.apply(json);
    try runtime.acknowledge();
    return changed;
}

fn buildScene(tree: *ui.Tree) !ui.Scene {
    return ui.Scene.fromTreeWithText(tree, @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()), .{ .measure_fn = text_backend.measure, .position_fn = text_backend.position, .styled_measure_fn = text_backend.measureStyled, .styled_position_fn = text_backend.positionStyled });
}

pub fn run() void {
    const smoke = getenv("SOLID_NATIVE_SMOKE") != null;
    var runtime = bridge.Runtime.init(source) catch |err| {
        std.log.err("Could not initialize Solid UI: {}", .{err});
        return;
    };
    defer runtime.deinit();
    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true, .window_hidden = smoke });
    rl.initWindow(window_width, window_height, "Solid + Zig experiment");
    defer rl.closeWindow();
    defer ui_cursor_shutdown();
    var renderer = @import("renderer.zig").Renderer.init(std.heap.page_allocator) catch |err| {
        std.log.err("Renderer initialization failed: {}", .{err});
        return;
    };
    defer renderer.deinit();
    var text_cache = text_backend.Cache.init(std.heap.page_allocator);
    defer text_cache.deinit();
    const watching = ui_watch_start() != 0;
    defer if (watching) ui_watch_stop();
    if (watching and !runtime.reload()) std.log.warn("Start dev:ui before dev:app to load development modules", .{});
    rl.setExitKey(.null);
    const event_waiting = !smoke and ui_wake_start() != 0;
    defer if (event_waiting) ui_wake_stop();
    if (event_waiting) {
        rl.enableEventWaiting();
    } else {
        std.log.warn("Timer wakeup unavailable; using 60 FPS event polling", .{});
        rl.disableEventWaiting();
        rl.setTargetFPS(60);
    }
    var timeline = ui.transitions.Timeline.init(std.heap.page_allocator);
    defer timeline.deinit();
    var tree = ui.Tree.init(std.heap.page_allocator);
    defer tree.deinit();
    _ = synchronize(&runtime, &tree) catch |err| {
        std.log.err("Could not initialize the native tree: {}", .{err});
        return;
    };
    var scene = buildScene(&tree) catch |err| {
        std.log.err("Could not build UI scene: {}", .{err});
        return;
    };
    defer scene.deinit();
    var scroll_offsets = std.AutoHashMap(u32, ui.ScrollOffset).init(std.heap.page_allocator);
    defer scroll_offsets.deinit();
    var focused: ?u32 = null;
    var editing: ?u32 = null;
    var editor = ui.TextEdit{};
    var last_width = rl.getScreenWidth();
    var last_height = rl.getScreenHeight();
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var smoke_frames: usize = 0;
    var last_hovered: ?u32 = null;
    var last_active: ?u32 = null;
    var last_focused: ?u32 = null;
    while (!rl.windowShouldClose()) {
        _ = scratch.reset(.retain_capacity);
        runtime.tick() catch |err| std.log.err("Async UI job failed: {}", .{err});
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const mouse = rl.getMousePosition();
            var allow_scroll = true;
            if (scene.pointerTarget(mouse.x, mouse.y)) |hit_id| {
                if (scene.find(hit_id)) |hit_item| {
                    if (!ui.interaction.touchActionAllowsPanY(hit_item.node.style.touchAction)) {
                        allow_scroll = false;
                    }
                }
            }
            if (allow_scroll) {
                _ = scene.chainWheel(mouse.x, mouse.y, 0, -wheel * 40, &scroll_offsets);
            }
        }
        if (watching and ui_watch_changed() != 0) {
            if (runtime.reload()) {
                std.log.info("Solid Refresh update applied", .{});
            } else {
                std.log.warn("Solid Refresh update failed", .{});
            }
        }
        if (rl.isMouseButtonPressed(.left)) {
            const mouse = rl.getMousePosition();
            focused = scene.hitTest(mouse.x, mouse.y);
            if (focused) |id| {
                if (scene.find(id)) |item| {
                    if (std.mem.eql(u8, item.node.type, "input")) {
                        if (editing != focused) {
                            editor = .{};
                            editing = focused;
                        }
                        const content = item.node.contentBox(item.bounds);
                        const local = scene.localPoint(item, mouse.x, mouse.y) orelse ui.transform.Point{ .x = mouse.x, .y = mouse.y };
                        const rel_x = local.x - content.x;
                        const idx = ui.text_edit.positionForX(item.node.value, rel_x, item.node.fontSize(), item.node.textContext(scene.text));
                        editor.move(idx, false);
                    }
                }
                runtime.click(id) catch |err| std.log.err("Click failed: {}", .{err});
            } else {
                runtime.click(0) catch {};
            }
        } else if (rl.isMouseButtonDown(.left)) {
            if (focused) |id| {
                if (scene.find(id)) |item| {
                    if (std.mem.eql(u8, item.node.type, "input")) {
                        const mouse = rl.getMousePosition();
                        const content = item.node.contentBox(item.bounds);
                        const local = scene.localPoint(item, mouse.x, mouse.y) orelse ui.transform.Point{ .x = mouse.x, .y = mouse.y };
                        const rel_x = local.x - content.x;
                        const idx = ui.text_edit.positionForX(item.node.value, rel_x, item.node.fontSize(), item.node.textContext(scene.text));
                        editor.move(idx, true);
                    }
                }
            }
        }
        if (rl.isKeyPressed(.tab)) {
            const ids = scene.getFocusOrder(scratch.allocator()) catch &.{};
            if (ids.len > 0) {
                var index: ?usize = null;
                for (ids, 0..) |id, i| if (focused == id) {
                    index = i;
                    break;
                };
                const reverse = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
                focused = ids[if (index) |i| (if (reverse) (i + ids.len - 1) % ids.len else (i + 1) % ids.len) else (if (reverse) ids.len - 1 else 0)];
            } else focused = null;
        }
        if (rl.isKeyPressed(.enter)) if (focused) |id| {
            if (scene.find(id)) |item| {
                if (!std.mem.eql(u8, item.node.type, "select")) {
                    runtime.click(id) catch {};
                }
            }
        };
        if (rl.isKeyPressed(.space)) if (focused) |id| {
            if (scene.find(id)) |item| {
                if (std.mem.eql(u8, item.node.type, "button")) {
                    runtime.click(id) catch {};
                }
            }
        };
        if (editing != focused) {
            editing = focused;
            editor = .{};
            if (focused) |id| if (scene.find(id)) |item| {
                editor.move(item.node.value.len, false);
            };
        }
        keyboard(&runtime, &scene, focused, &editor, scratch.allocator()) catch |err| std.log.err("Text input failed: {}", .{err});
        const changed = synchronize(&runtime, &tree) catch |err| {
            std.log.err("Could not update UI scene: {}", .{err});
            break;
        };
        if (changed or timeline.active() or wheel != 0 or last_width != rl.getScreenWidth() or last_height != rl.getScreenHeight()) {
            var next = buildScene(&tree) catch |err| {
                std.log.err("Could not lay out UI scene: {}", .{err});
                break;
            };
            if (changed) timeline.retarget(&scene, &next, rl.getTime()) catch |err| std.log.err("Transition retarget failed: {}", .{err});
            timeline.apply(&next, rl.getTime()) catch |err| std.log.err("Transition sample failed: {}", .{err});
            scene.deinit();
            scene = next;
            last_width = rl.getScreenWidth();
            last_height = rl.getScreenHeight();
            scene.applyScrollOffsets(&scroll_offsets);
            var offsets = scroll_offsets.keyIterator();
            while (offsets.next()) |id| {
                if (scene.find(id.*) == null) {
                    _ = scroll_offsets.remove(id.*);
                    offsets = scroll_offsets.keyIterator();
                }
            }
        }
        if (focused) |id| if (scene.find(id) == null) {
            focused = null;
        };
        const pointer = rl.getMousePosition();
        const hovered = if (scene.pointerTarget(pointer.x, pointer.y)) |id| scene.find(id) else null;
        const hovered_id = if (hovered) |h| h.node.id else null;
        if (hovered_id != last_hovered) {
            if (last_hovered) |old_id| runtime.hover(old_id, false) catch {};
            if (hovered_id) |new_id| runtime.hover(new_id, true) catch {};
            last_hovered = hovered_id;
        }
        const is_down = rl.isMouseButtonDown(.left);
        const active_id: ?u32 = if (is_down) hovered_id else null;
        if (active_id != last_active) {
            if (last_active) |old_id| runtime.active(old_id, false) catch {};
            if (active_id) |new_id| runtime.active(new_id, true) catch {};
            last_active = active_id;
        }
        if (focused != last_focused) {
            if (last_focused) |old_id| runtime.focus(old_id, false) catch {};
            if (focused) |new_id| runtime.focus(new_id, true) catch {};
            last_focused = focused;
        }
        const cursor = if (hovered) |h| h.node.style.cursor else "auto";
        ui_cursor_update(cursor.ptr, cursor.len, if (hovered) |h| (if (std.mem.eql(u8, h.node.type, "input") or std.mem.eql(u8, h.node.type, "text")) 1 else 0) else 0, if (hovered) |h| (if (h.node.clickable) 1 else 0) else 0);
        rl.beginDrawing();
        rl.clearBackground(background_color);
        var draw_context = DrawContext{ .focused = focused, .editor = &editor, .scroll_offsets = &scroll_offsets, .text_cache = &text_cache };
        renderer.render(&scene, &draw_context, drawItem, scratch.allocator()) catch |err| std.log.err("Could not render UI: {}", .{err});
        if (event_waiting) {
            const timeout = runtime.nextTimeout();
            ui_wake_schedule(if (timeline.active()) (if (timeout < 0) 1.0 / 60.0 else @min(timeout, 1.0 / 60.0)) else timeout);
        }
        rl.endDrawing();
        if (smoke) {
            smoke_frames += 1;
            if (smoke_frames >= 3) {
                std.log.info("Native application smoke completed: {d} scene items", .{scene.items.items.len});
                break;
            }
        }
    }
}
