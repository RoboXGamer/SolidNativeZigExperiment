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
fn renderScene(scene: *ui.Scene, focused: ?u32) !void {
    for (scene.items.items) |item| {
        const n = item.node;
        const b = item.bounds;
        const rect = rl.Rectangle{ .x = b.x, .y = b.y, .width = b.width, .height = b.height };
        const is_button = std.mem.eql(u8, n.type, "button");
        const radius = if (n.style.borderTopLeftRadius > 0) n.style.borderTopLeftRadius else n.style.borderRadius;
        // true overflow clipping: intersect with all overflow-hidden ancestors
        var clip_x = b.x;
        var clip_y = b.y;
        var clip_w = b.width;
        var clip_h = b.height;
        var has_clip = false;
        var cur_parent = item.parent_id;
        while (cur_parent) |pid| {
            // find item
            var found: ?ui.Item = null;
            for (scene.items.items) |it| { if (it.node.id == pid) { found = it; break; } }
            const pitem = found orelse break;
            if (std.mem.eql(u8, pitem.node.style.overflow, "hidden") or std.mem.eql(u8, pitem.node.style.overflow, "clip") or std.mem.eql(u8, pitem.node.style.overflow, "scroll")) {
                const pb = pitem.bounds;
                const nx = @max(clip_x, pb.x);
                const ny = @max(clip_y, pb.y);
                const nw = @min(clip_x + clip_w, pb.x + pb.width) - nx;
                const nh = @min(clip_y + clip_h, pb.y + pb.height) - ny;
                clip_x = nx; clip_y = ny; clip_w = @max(0, nw); clip_h = @max(0, nh);
                has_clip = true;
            }
            cur_parent = pitem.parent_id;
        }
        if (has_clip or std.mem.eql(u8, n.style.overflow, "hidden") or std.mem.eql(u8, n.style.overflow, "clip") or std.mem.eql(u8, n.style.overflow, "scroll")) {
            rl.beginScissorMode(@intFromFloat(clip_x), @intFromFloat(clip_y), @intFromFloat(clip_w), @intFromFloat(clip_h));
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
        if (std.mem.eql(u8, n.type, "input")) {
            rl.drawRectangleRec(rect, .dark_gray);
            const value = try scene.arena.allocator().dupeSentinel(u8, n.value, 0);
            rl.drawText(value, @intFromFloat(b.x + 10), @intFromFloat(b.y + 10), 20, .white);
        }
        if (focused == n.id) rl.drawRectangleLinesEx(rect, 2, .sky_blue);
        if (n.style.backgroundColor.len > 0 or is_button) {
            if (radius > 0) rl.drawRectangleRounded(rect, roundness(rect, radius), 8, color(n.style.backgroundColor, if (is_button) .dark_gray else .blank)) else rl.drawRectangleRec(rect, color(n.style.backgroundColor, if (is_button) .dark_gray else .blank));
        }
        // per-side borders
        const bt_w = if (n.style.borderTopWidth > 0) n.style.borderTopWidth else n.style.borderWidth;
        const br_w = if (n.style.borderRightWidth > 0) n.style.borderRightWidth else n.style.borderWidth;
        const bb_w = if (n.style.borderBottomWidth > 0) n.style.borderBottomWidth else n.style.borderWidth;
        const bl_w = if (n.style.borderLeftWidth > 0) n.style.borderLeftWidth else n.style.borderWidth;
        const uniform = (bt_w == br_w and br_w == bb_w and bb_w == bl_w);
        if (radius > 0 and uniform and bt_w > 0) {
            rl.drawRectangleRoundedLinesEx(rect, roundness(rect, radius), 8, bt_w, color(n.style.borderColor, .white));
        } else {
            if (bt_w > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.x + rect.width, .y = rect.y }, bt_w, color(if (n.style.borderTopColor.len > 0) n.style.borderTopColor else n.style.borderColor, .white));
            if (br_w > 0) rl.drawLineEx(.{ .x = rect.x + rect.width, .y = rect.y }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, br_w, color(if (n.style.borderRightColor.len > 0) n.style.borderRightColor else n.style.borderColor, .white));
            if (bb_w > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y + rect.height }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, bb_w, color(if (n.style.borderBottomColor.len > 0) n.style.borderBottomColor else n.style.borderColor, .white));
            if (bl_w > 0) rl.drawLineEx(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.x, .y = rect.y + rect.height }, bl_w, color(if (n.style.borderLeftColor.len > 0) n.style.borderLeftColor else n.style.borderColor, .white));
        }
        if (n.style.outlineWidth > 0) {
            const orect = rl.Rectangle{ .x = rect.x - n.style.outlineWidth, .y = rect.y - n.style.outlineWidth, .width = rect.width + 2 * n.style.outlineWidth, .height = rect.height + 2 * n.style.outlineWidth };
            rl.drawRectangleLinesEx(orect, n.style.outlineWidth, color(n.style.outlineColor, .white));
        }
        if (std.mem.eql(u8, n.type, "text") and n.text.len > 0) {
            const text = try scene.arena.allocator().dupeSentinel(u8, n.text, 0);
            const font_size: i32 = @intFromFloat(if (n.style.fontSize > 0) n.style.fontSize else 20);
            rl.drawText(text, @intFromFloat(b.x), @intFromFloat(b.y), font_size, color(n.style.color, .white));
        }
        if (std.mem.eql(u8, n.type, "input")) {
            rl.drawRectangleRec(rect, .dark_gray);
            const value = try scene.arena.allocator().dupeSentinel(u8, n.value, 0);
            rl.drawText(value, @intFromFloat(b.x + 10), @intFromFloat(b.y + 10), 20, .white);
        }
        if (focused == n.id) rl.drawRectangleLinesEx(rect, 2, .sky_blue);
        if (n.style.backgroundColor.len > 0 or is_button) {
            rl.drawRectangleRec(rect, color(n.style.backgroundColor, if (is_button) .dark_gray else .blank));
        }
        if (std.mem.eql(u8, n.type, "text") and n.text.len > 0) {
            const text = try scene.arena.allocator().dupeSentinel(u8, n.text, 0);
            const font_size: i32 = @intFromFloat(if (n.style.fontSize > 0) n.style.fontSize else 20);
            rl.drawText(text, @intFromFloat(b.x), @intFromFloat(b.y), font_size, color(n.style.color, .white));
        }
        if (std.mem.eql(u8, n.style.overflow, "hidden") or std.mem.eql(u8, n.style.overflow, "clip") or std.mem.eql(u8, n.style.overflow, "scroll")) {
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
    return ui.Scene.fromTree(tree, @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()));
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
