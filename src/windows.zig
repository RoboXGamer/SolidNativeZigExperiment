const rl = @import("raylib");

const window_width = 1280;
const window_height = 720;
const window_title = "Hello Zig!";
const window_flags = rl.ConfigFlags{ .window_resizable = true, .vsync_hint = true };
const exit_key = rl.KeyboardKey.null;
const target_fps = 60;
const background_color = rl.Color.init(51, 51, 51, 255);
const fps_x = 10;
const fps_y = 10;

pub fn run() void {
    rl.setConfigFlags(window_flags);
    rl.initWindow(window_width, window_height, window_title);
    defer rl.closeWindow();
    rl.setExitKey(exit_key);
    rl.setTargetFPS(target_fps);
    rl.enableEventWaiting();
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(background_color);
        rl.drawFPS(fps_x, fps_y);
        rl.endDrawing();
    }
}
