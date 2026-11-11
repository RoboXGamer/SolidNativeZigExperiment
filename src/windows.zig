const rl = @import("raylib");
const std = @import("std");
const ui = @import("ui_core");
const bridge = @import("solid_bridge");
extern fn ui_watch_start() c_int;
extern fn ui_watch_changed() c_int;
extern fn ui_watch_stop() void;
extern fn glfwWaitEvents() void;
extern fn glfwWaitEventsTimeout(timeout: f64) void;

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
        const chunk = @min(content.len - offset, buf.len - 1);
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

fn renderScene(scene: *ui.Scene, focused: ?u32) !void {
    for (scene.items.items) |item| {
        const n = item.node;
        const b = item.bounds;
        const rect = rl.Rectangle{ .x = b.x, .y = b.y, .width = b.width, .height = b.height };
        const is_button = std.mem.eql(u8, n.type, "button");
        const is_input = std.mem.eql(u8, n.type, "input");
        const radius = if (n.style.borderTopLeftRadius > 0) n.style.borderTopLeftRadius else n.style.borderRadius;

        // true overflow clipping: intersect with all overflow-hidden ancestors
        var clip = b;
        var has_clip = false;
        var cur_parent = item.parent_id;
        while (cur_parent) |pid| {
            var found: ?ui.Item = null;
            for (scene.items.items) |it| {
                if (it.node.id == pid) {
                    found = it;
                    break;
                }
            }
            const pitem = found orelse break;
            const ov = pitem.node.style.overflow;
            if (std.mem.eql(u8, ov, "hidden") or std.mem.eql(u8, ov, "clip") or std.mem.eql(u8, ov, "scroll")) {
                clip = clip.intersect(pitem.bounds);
                has_clip = true;
            }
            cur_parent = pitem.parent_id;
        }
        const self_overflow = std.mem.eql(u8, n.style.overflow, "hidden") or std.mem.eql(u8, n.style.overflow, "clip") or std.mem.eql(u8, n.style.overflow, "scroll");
        if (has_clip or self_overflow) {
            rl.beginScissorMode(@intFromFloat(clip.left()), @intFromFloat(clip.top()), @intFromFloat(clip.width), @intFromFloat(clip.height));
        }
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
            const text = try scene.arena.allocator().dupeSentinel(u8, n.text, 0);
            rl.drawText(text, @intFromFloat(b.x), @intFromFloat(b.y), font_size, color(n.style.color, .white));
        }
        if (std.mem.eql(u8, n.type, "input")) {
            const value = try scene.arena.allocator().dupeSentinel(u8, n.value, 0);
            const pad = n.padding();
            rl.drawText(value, @intFromFloat(b.x + pad.left), @intFromFloat(b.y + pad.top), font_size, .white);
        }
        if (focused == n.id) rl.drawRectangleLinesEx(rect, 2, .sky_blue);
        if (has_clip or self_overflow) {
            rl.endScissorMode();
        }
    }
}

fn keyboard(runtime: *bridge.Runtime, scene: *ui.Scene, focused: ?u32) !void {
    const id = focused orelse return;
    for (scene.items.items) |item| {
        if (item.node.id != id or !std.mem.eql(u8, item.node.type, "input")) continue;
        var value: std.ArrayList(u8) = .empty;
        const a = scene.arena.allocator();
        try value.appendSlice(a, item.node.value);
        var changed = false;
        if ((rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) and value.items.len > 0) {
            var end = value.items.len - 1;
            while (end > 0 and value.items[end] & 0xc0 == 0x80) end -= 1;
            value.shrinkRetainingCapacity(end);
            changed = true;
        }
        var codepoint = rl.getCharPressed();
        while (codepoint > 0) : (codepoint = rl.getCharPressed()) {
            var bytes: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(@intCast(codepoint), &bytes) catch continue;
            try value.appendSlice(a, bytes[0..len]);
            changed = true;
        }
        if (changed) try runtime.input(id, try a.dupeSentinel(u8, value.items, 0));
        return;
    }
}

fn buildScene(runtime: *bridge.Runtime, tree: *ui.Tree) !ui.Scene {
    const json = try runtime.snapshot();
    defer runtime.freeSnapshot(json);
    _ = try tree.apply(json);
    try runtime.acknowledge();
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
    rl.disableEventWaiting();
    var tree = ui.Tree.init(std.heap.page_allocator);
    defer tree.deinit();
    var scene = buildScene(&runtime, &tree) catch |err| {
        std.log.err("Could not build UI scene: {}", .{err});
        return;
    };
    defer scene.deinit();
    var focused: ?u32 = null;
    while (!rl.windowShouldClose()) {
        runtime.tick() catch |err| std.log.err("Async UI job failed: {}", .{err});
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
            var found = focused == null;
            var first: ?u32 = null;
            var selected: ?u32 = null;
            for (scene.items.items) |item| {
                if (!item.node.clickable) continue;
                if (first == null) first = item.node.id;
                if (found) {
                    selected = item.node.id;
                    break;
                }
                if (focused == item.node.id) found = true;
            }
            focused = selected orelse first;
        }
        if (rl.isKeyPressed(.enter)) if (focused) |id| runtime.click(id) catch {};
        keyboard(&runtime, &scene, focused) catch |err| std.log.err("Text input failed: {}", .{err});
        const next = buildScene(&runtime, &tree) catch |err| {
            std.log.err("Could not update UI scene: {}", .{err});
            break;
        };
        scene.deinit();
        scene = next;
        rl.beginDrawing();
        rl.clearBackground(background_color);
        renderScene(&scene, focused) catch |err| std.log.err("Could not render UI: {}", .{err});
        rl.endDrawing();
        const timeout = runtime.nextTimeout();
        if (timeout < 0) glfwWaitEvents() else if (timeout > 0) glfwWaitEventsTimeout(timeout);
    }
}
