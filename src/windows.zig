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
    if (value.len != 7 or value[0] != '#') return fallback;
    const rgb = std.fmt.parseInt(u32, value[1..], 16) catch return fallback;
    return rl.Color.init(@intCast((rgb >> 16) & 255), @intCast((rgb >> 8) & 255), @intCast(rgb & 255), 255);
}

fn roundness(rect: rl.Rectangle, radius: f32) f32 {
    const m = @min(rect.width, rect.height);
    if (m <= 0) return 0;
    return @min(1, radius / (m / 2));
}

/// Real font metrics for layout: Raylib owns the glyph atlas, so ask it for
/// advance widths instead of guessing per character. Chunked to keep a fixed
/// stack buffer for the NUL-terminated C string.
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
    return .{
        .width = @floatFromInt(total),
        .height = font_size,
        .ascent = font_size * ui.text.fallback_ascent_ratio,
    };
}

fn renderScene(scene: *ui.Scene, focused: ?u32, editor: *ui.TextEdit, allocator: std.mem.Allocator) !void {
    for (scene.items.items) |item| {
        const n = item.node;
        if (std.mem.eql(u8, n.type, "__layout_root")) continue;
        const b = item.bounds;
        const rect = rl.Rectangle{ .x = b.x, .y = b.y, .width = b.width, .height = b.height };
        const is_button = std.mem.eql(u8, n.type, "button");
        const is_input = std.mem.eql(u8, n.type, "input");
        const radius = if (n.style.borderTopLeftRadius > 0) n.style.borderTopLeftRadius else n.style.borderRadius;

        var clip = scene.clipFor(item);
        if (is_input) clip = clip.intersect(b);
        if (clip.isEmpty()) continue;
        rl.beginScissorMode(@intFromFloat(clip.left()), @intFromFloat(clip.top()), @intFromFloat(clip.width), @intFromFloat(clip.height));
        defer rl.endScissorMode();
        // box shadow (parsed: "ox oy blur spread color")
        if (n.style.boxShadow.len > 0) {
            var it = std.mem.tokenizeAny(u8, n.style.boxShadow, " ");
            const ox = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
            const oy = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
            const blur = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
            const spread = std.fmt.parseFloat(f32, it.next() orelse "0") catch 0;
            const cstr = it.next() orelse "#000000";
            const shad = rl.Rectangle{ .x = rect.x + ox - spread, .y = rect.y + oy - spread, .width = rect.width + 2 * spread, .height = rect.height + 2 * spread };
            rl.drawRectangleRounded(shad, roundness(shad, radius), 8, color(cstr, rl.Color.init(0, 0, 0, 128)));
            _ = blur;
        }
        if (n.style.backgroundColor.len > 0 or is_button or is_input) {
            const fallback: rl.Color = if (is_button) .dark_gray else if (is_input) .dark_gray else .blank;
            if (radius > 0) {
                rl.drawRectangleRounded(rect, roundness(rect, radius), 8, color(n.style.backgroundColor, fallback));
            } else {
                rl.drawRectangleRec(rect, color(n.style.backgroundColor, fallback));
            }
        }
        // per-side borders
        const bw = n.border();
        const uniform = (bw.top == bw.right and bw.right == bw.bottom and bw.bottom == bw.left);
        if (radius > 0 and uniform and bw.top > 0) {
            rl.drawRectangleRoundedLinesEx(rect, roundness(rect, radius), 8, bw.top, color(n.style.borderColor, .white));
        } else {
            if (bw.top > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.x + rect.width, .y = rect.y }, bw.top, color(if (n.style.borderTopColor.len > 0) n.style.borderTopColor else n.style.borderColor, .white));
            if (bw.right > 0) rl.drawLineEx(.{ .x = rect.x + rect.width, .y = rect.y }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, bw.right, color(if (n.style.borderRightColor.len > 0) n.style.borderRightColor else n.style.borderColor, .white));
            if (bw.bottom > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y + rect.height }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, bw.bottom, color(if (n.style.borderBottomColor.len > 0) n.style.borderBottomColor else n.style.borderColor, .white));
            if (bw.left > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.x, .y = rect.y + rect.height }, bw.left, color(if (n.style.borderLeftColor.len > 0) n.style.borderLeftColor else n.style.borderColor, .white));
        }
        if (n.style.outlineWidth > 0) {
            const orect = rl.Rectangle{ .x = rect.x - n.style.outlineWidth, .y = rect.y - n.style.outlineWidth, .width = rect.width + 2 * n.style.outlineWidth, .height = rect.height + 2 * n.style.outlineWidth };
            rl.drawRectangleLinesEx(orect, n.style.outlineWidth, color(n.style.outlineColor, .white));
        }
        const font_size: i32 = @intFromFloat(n.fontSize());
        if (std.mem.eql(u8, n.type, "text") and n.text.len > 0) {
            const text = try allocator.dupeSentinel(u8, n.text, 0);
            const content = n.contentBox(b);
            rl.drawText(text, @intFromFloat(content.x), @intFromFloat(content.y), font_size, color(n.style.color, .white));
        }
        if (std.mem.eql(u8, n.type, "input")) {
            const value = try allocator.dupeSentinel(u8, n.value, 0);
            const content = n.contentBox(b);
            var text_x = content.x;
            const text_y = content.y;
            if (focused == n.id) {
                editor.clamp(n.value);
                const caret = measureRaylib(null, n.value[0..editor.cursor], @floatFromInt(font_size)).width;
                text_x -= @max(0, caret - @max(0, content.width - 4));
                const selected = editor.selection();
                const start = measureRaylib(null, n.value[0..selected.start], @floatFromInt(font_size)).width;
                const end = measureRaylib(null, n.value[0..selected.end], @floatFromInt(font_size)).width;
                if (selected.start != selected.end) {
                    rl.drawRectangleRec(.{ .x = text_x + start, .y = text_y, .width = end - start, .height = @floatFromInt(font_size) }, .blue);
                } else {
                    rl.drawLineEx(.{ .x = text_x + caret, .y = text_y }, .{ .x = text_x + caret, .y = text_y + @as(f32, @floatFromInt(font_size)) }, 1, .white);
                }
            }
            rl.drawText(value, @intFromFloat(text_x), @intFromFloat(text_y), font_size, color(n.style.color, .white));
        }
        if (focused == n.id) rl.drawRectangleLinesEx(rect, 2, .sky_blue);
    }
}

fn pressed(key: rl.KeyboardKey) bool {
    return rl.isKeyPressed(key) or rl.isKeyPressedRepeat(key);
}

fn keyboard(runtime: *bridge.Runtime, scene: *ui.Scene, focused: ?u32, editor: *ui.TextEdit, allocator: std.mem.Allocator) !void {
    const item = scene.find(focused orelse return) orelse return;
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
    var scroll_offsets = std.AutoHashMap(u32, f32).init(std.heap.page_allocator);
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
            if (scene.scrollTarget(mouse.x, mouse.y)) |id| {
                const entry = scroll_offsets.getOrPut(id) catch break;
                if (!entry.found_existing) entry.value_ptr.* = 0;
                entry.value_ptr.* -= wheel * 40;
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
            if (focused) |id| runtime.click(id) catch |err| std.log.err("Click failed: {}", .{err});
        }
        if (rl.isKeyPressed(.tab)) {
            const reverse = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
            var found = focused == null;
            var first: ?u32 = null;
            var selected: ?u32 = null;
            var previous: ?u32 = null;
            for (scene.items.items) |item| {
                if (!item.node.clickable) continue;
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
            if (scene.find(id) != null) runtime.click(id) catch {};
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
            scene.applyScroll(&scroll_offsets);
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
        renderScene(&scene, focused, &editor, scratch.allocator()) catch |err| std.log.err("Could not render UI: {}", .{err});
        if (event_waiting) ui_wake_schedule(runtime.nextTimeout());
        rl.endDrawing();
    }
}
