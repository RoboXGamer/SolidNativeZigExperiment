const rl = @import("raylib");
const std = @import("std");
extern fn ui_init(source: [*]const u8, len: usize) c_int;
extern fn ui_eval(code: [*:0]const u8, out: [*]u8, capacity: usize) c_int;
extern fn ui_destroy() void;
extern fn ui_watch_start() c_int;
extern fn ui_watch_changed() c_int;
extern fn ui_watch_stop() void;
extern fn ui_reload() c_int;
const source = @embedFile("ui-bundle.js");
const window_width = 1280;
const window_height = 720;
const window_title = "Solid + Zig experiment";
const background_color = rl.Color.init(51, 51, 51, 255);
const button = rl.Rectangle{ .x = 50, .y = 120, .width = 180, .height = 50 };

fn evaluate(code: [*:0]const u8, buffer: *[256]u8) bool {
    return ui_eval(code, buffer, buffer.len) != 0;
}
pub fn run() void {
    if (ui_init(source.ptr, source.len) == 0) {
        ui_destroy();
        std.log.err("Could not initialize Solid UI", .{});
        return;
    }
    defer ui_destroy();
    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true });
    rl.initWindow(window_width, window_height, window_title);
    defer rl.closeWindow();
    const watching = ui_watch_start() != 0;
    defer if (watching) ui_watch_stop();
    rl.setExitKey(.null);
    rl.enableEventWaiting();
    var label: [256]u8 = undefined;
    var button_text: [256]u8 = undefined;
    if (!evaluate("uiLabel()", &label) or !evaluate("uiButton()", &button_text)) return;
    while (!rl.windowShouldClose()) {
        if (watching and ui_watch_changed() != 0) {
            if (ui_reload() != 0) {
                if (!evaluate("uiLabel()", &label) or !evaluate("uiButton()", &button_text)) break;
                std.log.info("Vite HMR applied Counter module: {s} / {s}", .{
                    std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&label)), 0),
                    std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&button_text)), 0),
                });
            } else {
                std.log.warn("Vite HMR update failed", .{});
            }
        }
        if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(rl.getMousePosition(), button)) {
            var ignored: [256]u8 = undefined;
            if (!evaluate("uiClick()", &ignored) or !evaluate("uiLabel()", &label)) break;
        }
        rl.beginDrawing();
        rl.clearBackground(background_color);
        rl.drawText(@ptrCast(&label), 50, 60, 30, .white);
        rl.drawRectangleRec(button, .dark_gray);
        rl.drawText(@ptrCast(&button_text), 65, 135, 20, .white);
        rl.endDrawing();
    }
}
