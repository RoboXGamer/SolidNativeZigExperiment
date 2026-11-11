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

const source = @embedFile("ui-bundle.js");
const window_width = 1280;
const window_height = 720;
const background_color = rl.Color.init(51, 51, 51, 255);

fn color(value: []const u8, fallback: rl.Color) rl.Color {
    return colorWithOpacity(value, fallback, 1.0);
}

fn colorWithOpacity(value: []const u8, fallback: rl.Color, opacity: f32) rl.Color {
    var c = fallback;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 7 and trimmed[0] == '#') {
        if (std.fmt.parseInt(u32, trimmed[1..], 16)) |rgb| {
            c = rl.Color.init(@intCast((rgb >> 16) & 255), @intCast((rgb >> 8) & 255), @intCast(rgb & 255), 255);
        } else |_| {}
    } else if (trimmed.len == 9 and trimmed[0] == '#') {
        if (std.fmt.parseInt(u32, trimmed[1..], 16)) |rgba| {
            c = rl.Color.init(@intCast((rgba >> 24) & 255), @intCast((rgba >> 16) & 255), @intCast((rgba >> 8) & 255), @intCast(rgba & 255));
        } else |_| {}
    } else if (std.mem.startsWith(u8, trimmed, "rgb(") or std.mem.startsWith(u8, trimmed, "rgba(")) {
        const start = std.mem.indexOfScalar(u8, trimmed, '(') orelse 0;
        const end = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse trimmed.len;
        var it = std.mem.tokenizeAny(u8, trimmed[start + 1 .. end], ",/ \t");
        const r_str = it.next();
        const g_str = it.next();
        const b_str = it.next();
        const a_str = it.next();
        if (r_str != null and g_str != null and b_str != null) {
            const r = std.fmt.parseInt(u8, std.mem.trim(u8, r_str.?, " "), 10) catch 0;
            const g = std.fmt.parseInt(u8, std.mem.trim(u8, g_str.?, " "), 10) catch 0;
            const b = std.fmt.parseInt(u8, std.mem.trim(u8, b_str.?, " "), 10) catch 0;
            var a: u8 = 255;
            if (a_str) |as| {
                const a_flt = std.fmt.parseFloat(f32, std.mem.trim(u8, as, " ")) catch 1.0;
                a = @intFromFloat(std.math.clamp(a_flt * 255.0, 0, 255));
            }
            c = rl.Color.init(r, g, b, a);
        }
    }
    const op = std.math.clamp(opacity, 0.0, 1.0);
    const alpha_f = @as(f32, @floatFromInt(c.a)) * op;
    c.a = @intFromFloat(std.math.clamp(alpha_f, 0, 255));
    return c;
}

fn roundness(rect: rl.Rectangle, radius: f32) f32 {
    const m = @min(rect.width, rect.height);
    if (m <= 0) return 0;
    return @min(1, radius / (m / 2));
}

/// Real font metrics for layout: Raylib owns the glyph atlas, so ask it for
fn measureRaylib(_: ?*anyopaque, content: []const u8, font_size: f32) ui.Metrics {
    const size: i32 = @intFromFloat(@max(1.0, @round(font_size)));
    var buf: [512]u8 = undefined;
    var total: i32 = 0;
    var offset: usize = 0;
    while (offset < content.len) {
        var chunk = @min(content.len - offset, buf.len - 1);
        while (offset + chunk < content.len and chunk > 0 and content[offset + chunk] & 0xc0 == 0x80) chunk -= 1;
        @memcpy(buf[0..chunk], content[offset .. offset + chunk]);
        buf[chunk] = 0;
        total += rl.measureText(buf[0..chunk :0], size);
        offset += chunk;
    }
    const h = font_size * ui.text.fallback_line_height_ratio;
    const asc = font_size * ui.text.fallback_ascent_ratio;
    const desc = font_size * ui.text.fallback_descent_ratio;
    return .{
        .width = @floatFromInt(total),
        .height = h,
        .ascent = asc,
        .descent = desc,
        .leading = @max(0, h - (asc + desc)),
    };
}

fn renderScene(scene: *ui.Scene, focused: ?u32, editor: *ui.TextEdit, scroll_offsets: *std.AutoHashMap(u32, ui.ScrollOffset), allocator: std.mem.Allocator) !void {
    const paint_order = try scene.getPaintOrder(allocator);
    defer allocator.free(paint_order);
    for (paint_order) |item_idx| {
        const item = scene.items.items[item_idx];
        const n = item.node;
        if (std.mem.eql(u8, n.type, "__layout_root")) continue;
        const b = item.bounds;
        var rect = rl.Rectangle{ .x = b.x, .y = b.y, .width = b.width, .height = b.height };
        if (n.style.transform.len > 0) {
            const mat = ui.transform.parseTransform(n.style.transform) catch ui.transform.Matrix2D.identity;
            rect.x += mat.tx;
            rect.y += mat.ty;
        }
        const is_button = std.mem.eql(u8, n.type, "button");
        const is_input = std.mem.eql(u8, n.type, "input");
        const is_select = std.mem.eql(u8, n.type, "select");
        const is_option = std.mem.eql(u8, n.type, "option");
        const radius = if (n.style.borderTopLeftRadius > 0) n.style.borderTopLeftRadius else n.style.borderRadius;
        const op = std.math.clamp(n.style.opacity, 0.0, 1.0);

        var clip = scene.clipFor(item);
        if (is_input) clip = clip.intersect(b);
        if (clip.isEmpty()) continue;
        const clip_x: i32 = @intFromFloat(@floor(clip.left()));
        const clip_y: i32 = @intFromFloat(@floor(clip.top()));
        const clip_w: i32 = @intFromFloat(@ceil(clip.width));
        const clip_h: i32 = @intFromFloat(@ceil(clip.height));
        rl.beginScissorMode(clip_x, clip_y, clip_w, clip_h);
        defer rl.endScissorMode();

        // multi-layer box shadow (supports comma-separated shadows)
        if (n.style.boxShadow.len > 0) {
            var layers = std.mem.tokenizeAny(u8, n.style.boxShadow, ",");
            while (layers.next()) |layer| {
                var it = std.mem.tokenizeAny(u8, std.mem.trim(u8, layer, " \t"), " ");
                const ox = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
                const oy = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
                const blur = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
                const spread = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
                const cstr = it.next() orelse "#000000";
                const shad = rl.Rectangle{ .x = rect.x + ox - spread, .y = rect.y + oy - spread, .width = rect.width + 2 * spread, .height = rect.height + 2 * spread };
                rl.drawRectangleRounded(shad, roundness(shad, radius + blur), 8, colorWithOpacity(cstr, rl.Color.init(0, 0, 0, 128), op));
            }
        }

        // background (gradient or solid)
        if (n.style.backgroundGradient.len > 0) {
            const grad_opt = ui.gradient.parseGradient(allocator, n.style.backgroundGradient) catch null;
            if (grad_opt) |g| {
                defer allocator.free(g.stops);
                if (g.stops.len >= 2) {
                    const c1 = rl.Color.init(g.stops[0].color[0], g.stops[0].color[1], g.stops[0].color[2], @intFromFloat(@as(f32, @floatFromInt(g.stops[0].color[3])) * op));
                    const c2 = rl.Color.init(g.stops[g.stops.len - 1].color[0], g.stops[g.stops.len - 1].color[1], g.stops[g.stops.len - 1].color[2], @intFromFloat(@as(f32, @floatFromInt(g.stops[g.stops.len - 1].color[3])) * op));
                    const is_horiz = (@abs(std.math.sin(g.angle_deg * (std.math.pi / 180.0))) > 0.707);
                    if (is_horiz) {
                        rl.drawRectangleGradientH(@intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.width), @intFromFloat(rect.height), c1, c2);
                    } else {
                        rl.drawRectangleGradientV(@intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.width), @intFromFloat(rect.height), c1, c2);
                    }
                } else {
                    rl.drawRectangleRec(rect, colorWithOpacity(n.style.backgroundColor, .dark_gray, op));
                }
            } else {
                rl.drawRectangleRec(rect, colorWithOpacity(n.style.backgroundColor, .dark_gray, op));
            }
        } else if (n.style.backgroundColor.len > 0 or is_button or is_input or is_select or is_option) {
            const fallback: rl.Color = if (is_button or is_select) .dark_gray else if (is_input) .dark_gray else if (is_option) rl.Color.init(40, 40, 40, 255) else .blank;
            if (radius > 0) {
                rl.drawRectangleRounded(rect, roundness(rect, radius), 8, colorWithOpacity(n.style.backgroundColor, fallback, op));
            } else {
                rl.drawRectangleRec(rect, colorWithOpacity(n.style.backgroundColor, fallback, op));
            }
        }

        // per-side borders
        const bw = n.border();
        const uniform = (bw.top == bw.right and bw.right == bw.bottom and bw.bottom == bw.left);
        if (radius > 0 and uniform and bw.top > 0) {
            rl.drawRectangleRoundedLinesEx(rect, roundness(rect, radius), 8, bw.top, colorWithOpacity(n.style.borderColor, .white, op));
        } else {
            if (bw.top > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.x + rect.width, .y = rect.y }, bw.top, colorWithOpacity(if (n.style.borderTopColor.len > 0) n.style.borderTopColor else n.style.borderColor, .white, op));
            if (bw.right > 0) rl.drawLineEx(.{ .x = rect.x + rect.width, .y = rect.y }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, bw.right, colorWithOpacity(if (n.style.borderRightColor.len > 0) n.style.borderRightColor else n.style.borderColor, .white, op));
            if (bw.bottom > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y + rect.height }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, bw.bottom, colorWithOpacity(if (n.style.borderBottomColor.len > 0) n.style.borderBottomColor else n.style.borderColor, .white, op));
            if (bw.left > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.x, .y = rect.y + rect.height }, bw.left, colorWithOpacity(if (n.style.borderLeftColor.len > 0) n.style.borderLeftColor else n.style.borderColor, .white, op));
        }
        if (n.style.outlineWidth > 0) {
            const orect = rl.Rectangle{ .x = rect.x - n.style.outlineWidth, .y = rect.y - n.style.outlineWidth, .width = rect.width + 2 * n.style.outlineWidth, .height = rect.height + 2 * n.style.outlineWidth };
            rl.drawRectangleLinesEx(orect, n.style.outlineWidth, colorWithOpacity(n.style.outlineColor, .white, op));
        }
        const font_size_int: i32 = @intFromFloat(@max(1.0, @round(n.fontSize())));
        if (std.mem.eql(u8, n.type, "text") and n.text.len > 0) {
            const content = n.contentBox(b);
            const line_h = if (n.style.lineHeight) |lh| (if (lh > 0) lh else scene.text.lineHeight(n.fontSize())) else scene.text.lineHeight(n.fontSize());
            const lines = scene.text.shapeLines(allocator, n.text, n.fontSize(), content.width, n.style.whiteSpace) catch &.{};
            for (lines, 0..) |sline, line_idx| {
                var line_x = content.x;
                if (std.mem.eql(u8, n.style.textAlign, "center")) {
                    line_x += @max(0, (content.width - sline.width) / 2);
                } else if (std.mem.eql(u8, n.style.textAlign, "right")) {
                    line_x += @max(0, content.width - sline.width);
                }
                const line_y = content.y + @as(f32, @floatFromInt(line_idx)) * line_h;
                const c_text = try allocator.dupeSentinel(u8, sline.text, 0);
                rl.drawText(c_text, @intFromFloat(@round(line_x)), @intFromFloat(@round(line_y)), font_size_int, colorWithOpacity(n.style.color, .white, op));
            }
        }
        if (std.mem.eql(u8, n.type, "select")) {
            const display_text = if (n.text.len > 0) n.text else n.value;
            const content = n.contentBox(b);
            if (display_text.len > 0) {
                const text = try allocator.dupeSentinel(u8, display_text, 0);
                rl.drawText(text, @intFromFloat(content.x), @intFromFloat(content.y), font_size_int, colorWithOpacity(n.style.color, .white, op));
            }
            const arrow_x = b.x + b.width - 20;
            if (arrow_x > content.x) {
                rl.drawText("v", @intFromFloat(arrow_x), @intFromFloat(content.y), font_size_int, colorWithOpacity(n.style.color, .light_gray, op));
            }
        }
        if (std.mem.eql(u8, n.type, "input")) {
            const value = try allocator.dupeSentinel(u8, n.value, 0);
            const content = n.contentBox(b);
            var text_x = content.x;
            const text_y = content.y;
            if (focused == n.id) {
                editor.clamp(n.value);
                const caret = measureRaylib(null, n.value[0..editor.cursor], @floatFromInt(font_size_int)).width;
                text_x -= @max(0, caret - @max(0, content.width - 4));
                const selected = editor.selection();
                const start = measureRaylib(null, n.value[0..selected.start], @floatFromInt(font_size_int)).width;
                const end = measureRaylib(null, n.value[0..selected.end], @floatFromInt(font_size_int)).width;
                if (selected.start != selected.end) {
                    rl.drawRectangleRec(.{ .x = text_x + start, .y = text_y, .width = end - start, .height = @floatFromInt(font_size_int) }, .blue);
                } else {
                    rl.drawLineEx(.{ .x = text_x + caret, .y = text_y }, .{ .x = text_x + caret, .y = text_y + @as(f32, @floatFromInt(font_size_int)) }, 1, .white);
                }
            }
            rl.drawText(value, @intFromFloat(text_x), @intFromFloat(text_y), font_size_int, colorWithOpacity(n.style.color, .white, op));
        }
        // Scrollbar rendering
        if (n.isScrollContainer() and !std.mem.eql(u8, n.style.scrollbarWidth, "none")) {
            const extent = scene.scrollExtent(n.id);
            if (extent.max_scroll_y > 0) {
                const track_w: f32 = if (std.mem.eql(u8, n.style.scrollbarWidth, "thin")) 4 else 8;
                const track_h = rect.height;
                const track_x = rect.x + rect.width - track_w;
                const track_y = rect.y;
                rl.drawRectangleRec(.{ .x = track_x, .y = track_y, .width = track_w, .height = track_h }, rl.Color.init(0, 0, 0, 40));
                const thumb_h = @max(16, track_h * (rect.height / extent.total_height));
                const cur_offset = if (scroll_offsets.get(n.id)) |so| so.y else 0;
                const thumb_y = track_y + (cur_offset / extent.max_scroll_y) * (track_h - thumb_h);
                rl.drawRectangleRec(.{ .x = track_x, .y = thumb_y, .width = track_w, .height = thumb_h }, rl.Color.init(255, 255, 255, 100));
            }
        }
        if (focused == n.id) rl.drawRectangleLinesEx(rect, 2, .sky_blue);
    }
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
    return ui.Scene.fromTreeWithText(tree, @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()), .{ .measure_fn = measureRaylib });
}

pub fn run() void {
    var runtime = bridge.Runtime.init(source) catch |err| {
        std.log.err("Could not initialize Solid UI: {}", .{err});
        return;
    };
    defer runtime.deinit();
    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true });
    rl.initWindow(window_width, window_height, "Solid + Zig experiment");
    defer rl.closeWindow();
    const watching = ui_watch_start() != 0;
    defer if (watching) ui_watch_stop();
    if (watching and !runtime.reload()) std.log.warn("Start dev:ui before dev:app to load development modules", .{});
    rl.setExitKey(.null);
    const event_waiting = ui_wake_start() != 0;
    defer if (event_waiting) ui_wake_stop();
    if (event_waiting) {
        rl.enableEventWaiting();
    } else {
        std.log.warn("Timer wakeup unavailable; using 60 FPS event polling", .{});
        rl.disableEventWaiting();
        rl.setTargetFPS(60);
    }
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
    while (!rl.windowShouldClose()) {
        _ = scratch.reset(.retain_capacity);
        runtime.tick() catch |err| std.log.err("Async UI job failed: {}", .{err});
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const mouse = rl.getMousePosition();
            _ = scene.chainWheel(mouse.x, mouse.y, 0, -wheel * 40, &scroll_offsets);
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
                        const content = item.node.contentBox(item.bounds);
                        const rel_x = mouse.x - content.x;
                        const idx = ui.text_edit.positionForX(item.node.value, rel_x, item.node.fontSize(), scene.text);
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
                        const rel_x = mouse.x - content.x;
                        const idx = ui.text_edit.positionForX(item.node.value, rel_x, item.node.fontSize(), scene.text);
                        editor.move(idx, true);
                    }
                }
            }
        }
        if (rl.isKeyPressed(.tab)) {
            const reverse = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
            var found = focused == null;
            var first: ?u32 = null;
            var selected: ?u32 = null;
            var previous: ?u32 = null;
            for (scene.items.items) |item| {
                if (!item.node.isFocusableForTab()) continue;
                if (first == null) first = item.node.id;
                if (reverse) {
                    if (focused == item.node.id) selected = previous;
                    previous = item.node.id;
                    continue;
                }
                if (found) {
                    selected = item.node.id;
                    break;
                }
                if (focused == item.node.id) found = true;
            }
            focused = selected orelse (if (reverse) previous else first);
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
        if (changed or wheel != 0 or last_width != rl.getScreenWidth() or last_height != rl.getScreenHeight()) {
            const next = buildScene(&tree) catch |err| {
                std.log.err("Could not lay out UI scene: {}", .{err});
                break;
            };
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
        rl.beginDrawing();
        rl.clearBackground(background_color);
        renderScene(&scene, focused, &editor, &scroll_offsets, scratch.allocator()) catch |err| std.log.err("Could not render UI: {}", .{err});
        if (event_waiting) ui_wake_schedule(runtime.nextTimeout());
        rl.endDrawing();
    }
}
