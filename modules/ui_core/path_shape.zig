//! CSS basic-shape path() implementation for clip-path and offset-path.
//! Implements SVG path data parsing (M, L, H, V, C, S, Q, T, A, Z),
//! fill-rule (nonzero, evenodd), bounding box computation, point-in-path
//! hit testing / clipping, and motion path evaluation (distance & angle).
const std = @import("std");
const geometry = @import("geometry.zig");
const Rect = geometry.Rect;

pub const FillRule = enum {
    nonzero,
    evenodd,

    pub fn fromString(str: []const u8) ?FillRule {
        const s = std.mem.trim(u8, str, " \t\r\n'\"");
        if (std.ascii.eqlIgnoreCase(s, "nonzero")) return .nonzero;
        if (std.ascii.eqlIgnoreCase(s, "evenodd")) return .evenodd;
        return null;
    }
};

pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn distance(self: Point, other: Point) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

pub const CommandType = enum {
    move_to,
    line_to,
    cubic_to,
    quad_to,
    arc_to,
    close,
};

pub const Command = struct {
    cmd: CommandType,
    params: [7]f32 = @splat(0),

    pub fn moveTo(x: f32, y: f32) Command {
        var c = Command{ .cmd = .move_to };
        c.params[0] = x;
        c.params[1] = y;
        return c;
    }

    pub fn lineTo(x: f32, y: f32) Command {
        var c = Command{ .cmd = .line_to };
        c.params[0] = x;
        c.params[1] = y;
        return c;
    }

    pub fn cubicTo(x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) Command {
        var c = Command{ .cmd = .cubic_to };
        c.params[0] = x1;
        c.params[1] = y1;
        c.params[2] = x2;
        c.params[3] = y2;
        c.params[4] = x;
        c.params[5] = y;
        return c;
    }

    pub fn quadTo(x1: f32, y1: f32, x: f32, y: f32) Command {
        var c = Command{ .cmd = .quad_to };
        c.params[0] = x1;
        c.params[1] = y1;
        c.params[2] = x;
        c.params[3] = y;
        return c;
    }

    pub fn arcTo(rx: f32, ry: f32, rot: f32, large: bool, sweep: bool, x: f32, y: f32) Command {
        var c = Command{ .cmd = .arc_to };
        c.params[0] = rx;
        c.params[1] = ry;
        c.params[2] = rot;
        c.params[3] = if (large) 1.0 else 0.0;
        c.params[4] = if (sweep) 1.0 else 0.0;
        c.params[5] = x;
        c.params[6] = y;
        return c;
    }

    pub fn close() Command {
        return Command{ .cmd = .close };
    }
};

pub const Path = struct {
    commands: []const Command,
    fill_rule: FillRule = .nonzero,

    pub fn init(commands: []const Command, fill_rule: FillRule) Path {
        return .{
            .commands = commands,
            .fill_rule = fill_rule,
        };
    }

    /// Compute axis-aligned bounding box of the path.
    pub fn computeBounds(self: Path) Rect {
        if (self.commands.len == 0) return Rect.zero;
        var min_x: f32 = std.math.inf(f32);
        var min_y: f32 = std.math.inf(f32);
        var max_x: f32 = -std.math.inf(f32);
        var max_y: f32 = -std.math.inf(f32);

        var cur_x: f32 = 0;
        var cur_y: f32 = 0;

        for (self.commands) |cmd| {
            switch (cmd.cmd) {
                .move_to => {
                    cur_x = cmd.params[0];
                    cur_y = cmd.params[1];
                    min_x = @min(min_x, cur_x);
                    min_y = @min(min_y, cur_y);
                    max_x = @max(max_x, cur_x);
                    max_y = @max(max_y, cur_y);
                },
                .line_to => {
                    cur_x = cmd.params[0];
                    cur_y = cmd.params[1];
                    min_x = @min(min_x, cur_x);
                    min_y = @min(min_y, cur_y);
                    max_x = @max(max_x, cur_x);
                    max_y = @max(max_y, cur_y);
                },
                .quad_to => {
                    min_x = @min(min_x, @min(cmd.params[0], cmd.params[2]));
                    min_y = @min(min_y, @min(cmd.params[1], cmd.params[3]));
                    max_x = @max(max_x, @max(cmd.params[0], cmd.params[2]));
                    max_y = @max(max_y, @max(cmd.params[1], cmd.params[3]));
                    cur_x = cmd.params[2];
                    cur_y = cmd.params[3];
                },
                .cubic_to => {
                    min_x = @min(min_x, @min(cmd.params[0], @min(cmd.params[2], cmd.params[4])));
                    min_y = @min(min_y, @min(cmd.params[1], @min(cmd.params[3], cmd.params[5])));
                    max_x = @max(max_x, @max(cmd.params[0], @max(cmd.params[2], cmd.params[4])));
                    max_y = @max(max_y, @max(cmd.params[1], @max(cmd.params[3], cmd.params[5])));
                    cur_x = cmd.params[4];
                    cur_y = cmd.params[5];
                },
                .arc_to => {
                    cur_x = cmd.params[5];
                    cur_y = cmd.params[6];
                    min_x = @min(min_x, cur_x);
                    min_y = @min(min_y, cur_y);
                    max_x = @max(max_x, cur_x);
                    max_y = @max(max_y, cur_y);
                },
                .close => {},
            }
        }
        if (min_x > max_x) return Rect.zero;
        return .{
            .x = min_x,
            .y = min_y,
            .width = @max(0, max_x - min_x),
            .height = @max(0, max_y - min_y),
        };
    }

    /// Approximate total length of the path by summing segment distances.
    pub fn totalLength(self: Path) f32 {
        var length: f32 = 0;
        var cur_x: f32 = 0;
        var cur_y: f32 = 0;
        var start_x: f32 = 0;
        var start_y: f32 = 0;

        for (self.commands) |cmd| {
            switch (cmd.cmd) {
                .move_to => {
                    cur_x = cmd.params[0];
                    cur_y = cmd.params[1];
                    start_x = cur_x;
                    start_y = cur_y;
                },
                .line_to => {
                    const nx = cmd.params[0];
                    const ny = cmd.params[1];
                    const dx = nx - cur_x;
                    const dy = ny - cur_y;
                    length += @sqrt(dx * dx + dy * dy);
                    cur_x = nx;
                    cur_y = ny;
                },
                .quad_to => {
                    // Approximate quad with 4 segments
                    var px = cur_x;
                    var py = cur_y;
                    var step: usize = 1;
                    while (step <= 4) : (step += 1) {
                        const t = @as(f32, @floatFromInt(step)) / 4.0;
                        const it = 1.0 - t;
                        const nx = it * it * cur_x + 2.0 * it * t * cmd.params[0] + t * t * cmd.params[2];
                        const ny = it * it * cur_y + 2.0 * it * t * cmd.params[1] + t * t * cmd.params[3];
                        const dx = nx - px;
                        const dy = ny - py;
                        length += @sqrt(dx * dx + dy * dy);
                        px = nx;
                        py = ny;
                    }
                    cur_x = cmd.params[2];
                    cur_y = cmd.params[3];
                },
                .cubic_to => {
                    // Approximate cubic with 8 segments
                    var px = cur_x;
                    var py = cur_y;
                    var step: usize = 1;
                    while (step <= 8) : (step += 1) {
                        const t = @as(f32, @floatFromInt(step)) / 8.0;
                        const it = 1.0 - t;
                        const nx = it * it * it * cur_x + 3.0 * it * it * t * cmd.params[0] + 3.0 * it * t * t * cmd.params[2] + t * t * t * cmd.params[4];
                        const ny = it * it * it * cur_y + 3.0 * it * it * t * cmd.params[1] + 3.0 * it * t * t * cmd.params[3] + t * t * t * cmd.params[5];
                        const dx = nx - px;
                        const dy = ny - py;
                        length += @sqrt(dx * dx + dy * dy);
                        px = nx;
                        py = ny;
                    }
                    cur_x = cmd.params[4];
                    cur_y = cmd.params[5];
                },
                .arc_to => {
                    const nx = cmd.params[5];
                    const ny = cmd.params[6];
                    const dx = nx - cur_x;
                    const dy = ny - cur_y;
                    length += @sqrt(dx * dx + dy * dy);
                    cur_x = nx;
                    cur_y = ny;
                },
                .close => {
                    const dx = start_x - cur_x;
                    const dy = start_y - cur_y;
                    length += @sqrt(dx * dx + dy * dy);
                    cur_x = start_x;
                    cur_y = start_y;
                },
            }
        }
        return length;
    }

    pub const PointAndAngle = struct {
        point: Point,
        angle_radians: f32 = 0,
    };

    /// Compute point and tangent direction at specified distance along the path.
    pub fn pointAtDistance(self: Path, distance: f32) PointAndAngle {
        const total = self.totalLength();
        if (total <= 0 or self.commands.len == 0) return .{ .point = .{} };
        const target = @max(0, @min(total, distance));

        var accumulated: f32 = 0;
        var cur_x: f32 = 0;
        var cur_y: f32 = 0;
        var start_x: f32 = 0;
        var start_y: f32 = 0;

        for (self.commands) |cmd| {
            switch (cmd.cmd) {
                .move_to => {
                    cur_x = cmd.params[0];
                    cur_y = cmd.params[1];
                    start_x = cur_x;
                    start_y = cur_y;
                },
                .line_to => {
                    const nx = cmd.params[0];
                    const ny = cmd.params[1];
                    const dx = nx - cur_x;
                    const dy = ny - cur_y;
                    const seg_len = @sqrt(dx * dx + dy * dy);
                    if (accumulated + seg_len >= target and seg_len > 0) {
                        const t = (target - accumulated) / seg_len;
                        return .{
                            .point = .{ .x = cur_x + dx * t, .y = cur_y + dy * t },
                            .angle_radians = std.math.atan2(dy, dx),
                        };
                    }
                    accumulated += seg_len;
                    cur_x = nx;
                    cur_y = ny;
                },
                .quad_to => {
                    var px = cur_x;
                    var py = cur_y;
                    var step: usize = 1;
                    while (step <= 4) : (step += 1) {
                        const t_val = @as(f32, @floatFromInt(step)) / 4.0;
                        const it = 1.0 - t_val;
                        const nx = it * it * cur_x + 2.0 * it * t_val * cmd.params[0] + t_val * t_val * cmd.params[2];
                        const ny = it * it * cur_y + 2.0 * it * t_val * cmd.params[1] + t_val * t_val * cmd.params[3];
                        const dx = nx - px;
                        const dy = ny - py;
                        const seg_len = @sqrt(dx * dx + dy * dy);
                        if (accumulated + seg_len >= target and seg_len > 0) {
                            const subt = (target - accumulated) / seg_len;
                            return .{
                                .point = .{ .x = px + dx * subt, .y = py + dy * subt },
                                .angle_radians = std.math.atan2(dy, dx),
                            };
                        }
                        accumulated += seg_len;
                        px = nx;
                        py = ny;
                    }
                    cur_x = cmd.params[2];
                    cur_y = cmd.params[3];
                },
                .cubic_to => {
                    var px = cur_x;
                    var py = cur_y;
                    var step: usize = 1;
                    while (step <= 8) : (step += 1) {
                        const t_val = @as(f32, @floatFromInt(step)) / 8.0;
                        const it = 1.0 - t_val;
                        const nx = it * it * it * cur_x + 3.0 * it * it * t_val * cmd.params[0] + 3.0 * it * t_val * t_val * cmd.params[2] + t_val * t_val * t_val * cmd.params[4];
                        const ny = it * it * it * cur_y + 3.0 * it * it * t_val * cmd.params[1] + 3.0 * it * t_val * t_val * cmd.params[3] + t_val * t_val * t_val * cmd.params[5];
                        const dx = nx - px;
                        const dy = ny - py;
                        const seg_len = @sqrt(dx * dx + dy * dy);
                        if (accumulated + seg_len >= target and seg_len > 0) {
                            const subt = (target - accumulated) / seg_len;
                            return .{
                                .point = .{ .x = px + dx * subt, .y = py + dy * subt },
                                .angle_radians = std.math.atan2(dy, dx),
                            };
                        }
                        accumulated += seg_len;
                        px = nx;
                        py = ny;
                    }
                    cur_x = cmd.params[4];
                    cur_y = cmd.params[5];
                },
                .arc_to => {
                    const nx = cmd.params[5];
                    const ny = cmd.params[6];
                    const dx = nx - cur_x;
                    const dy = ny - cur_y;
                    const seg_len = @sqrt(dx * dx + dy * dy);
                    if (accumulated + seg_len >= target and seg_len > 0) {
                        const t = (target - accumulated) / seg_len;
                        return .{
                            .point = .{ .x = cur_x + dx * t, .y = cur_y + dy * t },
                            .angle_radians = std.math.atan2(dy, dx),
                        };
                    }
                    accumulated += seg_len;
                    cur_x = nx;
                    cur_y = ny;
                },
                .close => {
                    const dx = start_x - cur_x;
                    const dy = start_y - cur_y;
                    const seg_len = @sqrt(dx * dx + dy * dy);
                    if (accumulated + seg_len >= target and seg_len > 0) {
                        const t = (target - accumulated) / seg_len;
                        return .{
                            .point = .{ .x = cur_x + dx * t, .y = cur_y + dy * t },
                            .angle_radians = std.math.atan2(dy, dx),
                        };
                    }
                    accumulated += seg_len;
                    cur_x = start_x;
                    cur_y = start_y;
                },
            }
        }
        return .{ .point = .{ .x = cur_x, .y = cur_y } };
    }

    pub fn pointAtFraction(self: Path, fraction: f32) PointAndAngle {
        const total = self.totalLength();
        const f = @max(0, @min(1.0, fraction));
        return self.pointAtDistance(f * total);
    }

    /// Point-in-polygon / point-in-path test supporting nonzero and evenodd fill rules.
    pub fn contains(self: Path, px: f32, py: f32) bool {
        var crossings: i32 = 0;
        var winding: i32 = 0;

        var cur_x: f32 = 0;
        var cur_y: f32 = 0;
        var start_x: f32 = 0;
        var start_y: f32 = 0;

        for (self.commands) |cmd| {
            switch (cmd.cmd) {
                .move_to => {
                    cur_x = cmd.params[0];
                    cur_y = cmd.params[1];
                    start_x = cur_x;
                    start_y = cur_y;
                },
                .line_to => {
                    const nx = cmd.params[0];
                    const ny = cmd.params[1];
                    testSegment(cur_x, cur_y, nx, ny, px, py, &crossings, &winding);
                    cur_x = nx;
                    cur_y = ny;
                },
                .quad_to => {
                    var x0 = cur_x;
                    var y0 = cur_y;
                    var step: usize = 1;
                    while (step <= 4) : (step += 1) {
                        const t = @as(f32, @floatFromInt(step)) / 4.0;
                        const it = 1.0 - t;
                        const nx = it * it * cur_x + 2.0 * it * t * cmd.params[0] + t * t * cmd.params[2];
                        const ny = it * it * cur_y + 2.0 * it * t * cmd.params[1] + t * t * cmd.params[3];
                        testSegment(x0, y0, nx, ny, px, py, &crossings, &winding);
                        x0 = nx;
                        y0 = ny;
                    }
                    cur_x = cmd.params[2];
                    cur_y = cmd.params[3];
                },
                .cubic_to => {
                    var x0 = cur_x;
                    var y0 = cur_y;
                    var step: usize = 1;
                    while (step <= 8) : (step += 1) {
                        const t = @as(f32, @floatFromInt(step)) / 8.0;
                        const it = 1.0 - t;
                        const nx = it * it * it * cur_x + 3.0 * it * it * t * cmd.params[0] + 3.0 * it * t * t * cmd.params[2] + t * t * t * cmd.params[4];
                        const ny = it * it * it * cur_y + 3.0 * it * it * t * cmd.params[1] + 3.0 * it * t * t * cmd.params[3] + t * t * t * cmd.params[5];
                        testSegment(x0, y0, nx, ny, px, py, &crossings, &winding);
                        x0 = nx;
                        y0 = ny;
                    }
                    cur_x = cmd.params[4];
                    cur_y = cmd.params[5];
                },
                .arc_to => {
                    const nx = cmd.params[5];
                    const ny = cmd.params[6];
                    testSegment(cur_x, cur_y, nx, ny, px, py, &crossings, &winding);
                    cur_x = nx;
                    cur_y = ny;
                },
                .close => {
                    testSegment(cur_x, cur_y, start_x, start_y, px, py, &crossings, &winding);
                    cur_x = start_x;
                    cur_y = start_y;
                },
            }
        }

        return switch (self.fill_rule) {
            .evenodd => @mod(crossings, 2) != 0,
            .nonzero => winding != 0,
        };
    }

    fn testSegment(x1: f32, y1: f32, x2: f32, y2: f32, px: f32, py: f32, crossings: *i32, winding: *i32) void {
        if ((y1 <= py and y2 > py) or (y2 <= py and y1 > py)) {
            const vt = (py - y1) / (y2 - y1);
            const ix = x1 + vt * (x2 - x1);
            if (px < ix) {
                crossings.* += 1;
                if (y1 < y2) {
                    winding.* += 1;
                } else {
                    winding.* -= 1;
                }
            }
        }
    }
};

/// Parser for SVG path data commands.
pub const PathParser = struct {
    input: []const u8,
    cursor: usize = 0,

    pub fn init(input: []const u8) PathParser {
        return .{ .input = input };
    }

    fn skipWhitespace(self: *PathParser) void {
        while (self.cursor < self.input.len) {
            const c = self.input[self.cursor];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ',') {
                self.cursor += 1;
            } else {
                break;
            }
        }
    }

    fn parseNumber(self: *PathParser) ?f32 {
        self.skipWhitespace();
        if (self.cursor >= self.input.len) return null;
        const start = self.cursor;
        var has_digits = false;

        if (self.cursor < self.input.len and (self.input[self.cursor] == '+' or self.input[self.cursor] == '-')) {
            self.cursor += 1;
        }
        while (self.cursor < self.input.len and std.ascii.isDigit(self.input[self.cursor])) {
            has_digits = true;
            self.cursor += 1;
        }
        if (self.cursor < self.input.len and self.input[self.cursor] == '.') {
            self.cursor += 1;
            while (self.cursor < self.input.len and std.ascii.isDigit(self.input[self.cursor])) {
                has_digits = true;
                self.cursor += 1;
            }
        }
        if (has_digits and self.cursor < self.input.len and (self.input[self.cursor] == 'e' or self.input[self.cursor] == 'E')) {
            const exp_start = self.cursor;
            self.cursor += 1;
            if (self.cursor < self.input.len and (self.input[self.cursor] == '+' or self.input[self.cursor] == '-')) {
                self.cursor += 1;
            }
            var has_exp_digits = false;
            while (self.cursor < self.input.len and std.ascii.isDigit(self.input[self.cursor])) {
                has_exp_digits = true;
                self.cursor += 1;
            }
            if (!has_exp_digits) {
                self.cursor = exp_start;
            }
        }

        if (!has_digits) {
            self.cursor = start;
            return null;
        }

        const slice = self.input[start..self.cursor];
        return std.fmt.parseFloat(f32, slice) catch null;
    }

    pub fn parse(self: *PathParser, allocator: std.mem.Allocator, fill_rule: FillRule) !Path {
        var commands: std.ArrayList(Command) = .empty;
        errdefer commands.deinit(allocator);

        var cur_x: f32 = 0;
        var cur_y: f32 = 0;
        var start_x: f32 = 0;
        var start_y: f32 = 0;
        var last_control_x: ?f32 = null;
        var last_control_y: ?f32 = null;
        var current_cmd: u8 = 0;

        while (true) {
            self.skipWhitespace();
            if (self.cursor >= self.input.len) break;

            const ch = self.input[self.cursor];
            if (std.ascii.isAlphabetic(ch)) {
                current_cmd = ch;
                self.cursor += 1;
            }

            const is_relative = std.ascii.isLower(current_cmd);
            const cmd_upper = std.ascii.toUpper(current_cmd);

            switch (cmd_upper) {
                'M' => {
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.moveTo(x, y));
                    cur_x = x;
                    cur_y = y;
                    start_x = x;
                    start_y = y;
                    last_control_x = null;
                    last_control_y = null;
                    // Subsequent coordinates become implicit LineTo
                    current_cmd = if (is_relative) 'l' else 'L';
                },
                'L' => {
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.lineTo(x, y));
                    cur_x = x;
                    cur_y = y;
                    last_control_x = null;
                    last_control_y = null;
                },
                'H' => {
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    try commands.append(allocator, Command.lineTo(x, cur_y));
                    cur_x = x;
                    last_control_x = null;
                    last_control_y = null;
                },
                'V' => {
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.lineTo(cur_x, y));
                    cur_y = y;
                    last_control_x = null;
                    last_control_y = null;
                },
                'C' => {
                    const x1 = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y1 = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    const x2 = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y2 = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.cubicTo(x1, y1, x2, y2, x, y));
                    last_control_x = x2;
                    last_control_y = y2;
                    cur_x = x;
                    cur_y = y;
                },
                'S' => {
                    var x1 = cur_x;
                    var y1 = cur_y;
                    if (last_control_x != null and last_control_y != null) {
                        x1 = 2.0 * cur_x - last_control_x.?;
                        y1 = 2.0 * cur_y - last_control_y.?;
                    }
                    const x2 = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y2 = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.cubicTo(x1, y1, x2, y2, x, y));
                    last_control_x = x2;
                    last_control_y = y2;
                    cur_x = x;
                    cur_y = y;
                },
                'Q' => {
                    const x1 = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y1 = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.quadTo(x1, y1, x, y));
                    last_control_x = x1;
                    last_control_y = y1;
                    cur_x = x;
                    cur_y = y;
                },
                'T' => {
                    var x1 = cur_x;
                    var y1 = cur_y;
                    if (last_control_x != null and last_control_y != null) {
                        x1 = 2.0 * cur_x - last_control_x.?;
                        y1 = 2.0 * cur_y - last_control_y.?;
                    }
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.quadTo(x1, y1, x, y));
                    last_control_x = x1;
                    last_control_y = y1;
                    cur_x = x;
                    cur_y = y;
                },
                'A' => {
                    const rx = self.parseNumber() orelse break;
                    const ry = self.parseNumber() orelse break;
                    const rot = self.parseNumber() orelse break;
                    const large = (self.parseNumber() orelse break) != 0;
                    const sweep = (self.parseNumber() orelse break) != 0;
                    const x = (self.parseNumber() orelse break) + if (is_relative) cur_x else 0;
                    const y = (self.parseNumber() orelse break) + if (is_relative) cur_y else 0;
                    try commands.append(allocator, Command.arcTo(rx, ry, rot, large, sweep, x, y));
                    cur_x = x;
                    cur_y = y;
                    last_control_x = null;
                    last_control_y = null;
                },
                'Z' => {
                    try commands.append(allocator, Command.close());
                    cur_x = start_x;
                    cur_y = start_y;
                    last_control_x = null;
                    last_control_y = null;
                },
                else => {
                    // Unknown token, advance
                    self.cursor += 1;
                },
            }
        }

        return Path.init(try commands.toOwnedSlice(allocator), fill_rule);
    }
};

/// Parse a CSS path() functional notation: `path([<fill-rule>,] <string>)`.
pub fn parseCssPath(allocator: std.mem.Allocator, input: []const u8) !Path {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    var fill_rule: FillRule = .nonzero;
    var d_slice = trimmed;

    if (std.mem.startsWith(u8, trimmed, "path(") and std.mem.endsWith(u8, trimmed, ")")) {
        const inner = std.mem.trim(u8, trimmed[5 .. trimmed.len - 1], " \t\r\n");
        // Check for fill-rule before comma
        if (std.mem.indexOfScalar(u8, inner, ',')) |comma_idx| {
            const rule_part = inner[0..comma_idx];
            if (FillRule.fromString(rule_part)) |rule| {
                fill_rule = rule;
                d_slice = std.mem.trim(u8, inner[comma_idx + 1 ..], " \t\r\n");
            }
        } else {
            d_slice = inner;
        }
    }

    // Strip quotes around SVG path string if present
    if (d_slice.len >= 2 and ((d_slice[0] == '"' and d_slice[d_slice.len - 1] == '"') or (d_slice[0] == '\'' and d_slice[d_slice.len - 1] == '\''))) {
        d_slice = d_slice[1 .. d_slice.len - 1];
    }

    var parser = PathParser.init(d_slice);
    return parser.parse(allocator, fill_rule);
}
