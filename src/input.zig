//! One input snapshot consumed by normal focus/hit-test/edit/scroll operations.
const rl = @import("raylib");
const std = @import("std");
pub const Input = struct {
    pub const key_names = [_][]const u8{ "Tab", "Enter", "Escape", "Space", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "Backspace", "Delete", "Shift", "Control", "a", "c", "x", "v" };
    pointer: rl.Vector2 = .{ .x = -10, .y = -10 },
    inside: bool = true,
    down: bool = false,
    press: bool = false,
    release: bool = false,
    wheel_x: f32 = 0,
    wheel_y: f32 = 0,
    keys: [512]bool = @splat(false),
    presses: [512]bool = @splat(false),
    text: [4096]u8 = undefined,
    text_len: usize = 0,
    pub fn isKeyDown(self: *const Input, key: rl.KeyboardKey) bool {
        return self.keys[@intCast(@backingInt(key))];
    }
    pub fn isKeyPressed(self: *const Input, key: rl.KeyboardKey) bool {
        return self.presses[@intCast(@backingInt(key))];
    }
    pub fn next(self: *Input) void {
        self.press = false;
        self.release = false;
        self.presses = @splat(false);
        self.text_len = 0;
        self.wheel_x = 0;
        self.wheel_y = 0;
    }
    pub fn native() Input {
        var s: Input = .{ .pointer = rl.getMousePosition(), .inside = rl.isCursorOnScreen(), .down = rl.isMouseButtonDown(.left), .press = rl.isMouseButtonPressed(.left), .release = rl.isMouseButtonReleased(.left), .wheel_y = -rl.getMouseWheelMove() * 40 };
        inline for (@typeInfo(rl.KeyboardKey).@"enum".field_values) |v| {
            if (v >= 0 and v < 512) {
                const k: rl.KeyboardKey = @fromBackingInt(@intCast(v));
                s.keys[v] = rl.isKeyDown(k);
                s.presses[v] = rl.isKeyPressed(k) or rl.isKeyPressedRepeat(k);
            }
        }
        var cp = rl.getCharPressed();
        while (cp > 0) : (cp = rl.getCharPressed()) {
            var bytes: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(@intCast(cp), &bytes) catch continue;
            if (cp >= 32 and s.text_len + len <= s.text.len) {
                @memcpy(s.text[s.text_len..][0..len], bytes[0..len]);
                s.text_len += len;
            }
        }
        if (!rl.isWindowFocused()) {
            s.down = false;
            s.keys = @splat(false);
        }
        return s;
    }
    pub fn parseKey(name: []const u8) !rl.KeyboardKey {
        const values = [_]rl.KeyboardKey{ .tab, .enter, .escape, .space, .up, .down, .left, .right, .home, .end, .backspace, .delete, .left_shift, .left_control, .a, .c, .x, .v };
        inline for (key_names, values) |n, v| if (std.mem.eql(u8, name, n)) return v;
        return error.UnsupportedKey;
    }
};
