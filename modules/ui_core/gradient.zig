//! CSS Gradient parsing and color interpolation (Issues #293, #297).
//! Supports linear-gradient, radial-gradient, and conic-gradient.
const std = @import("std");

pub const ColorStop = struct {
    color: [4]u8, // RGBA
    position: ?f32 = null, // 0.0 to 1.0
};

pub const GradientKind = enum {
    linear,
    radial,
    conic,
};

pub const Gradient = struct {
    kind: GradientKind,
    angle_deg: f32 = 180.0, // linear direction (180 = to bottom) or conic start angle
    center_x: f32 = 0.5, // 0.0 to 1.0
    center_y: f32 = 0.5,
    stops: []const ColorStop,
    circle: bool = false,
    closest_side: bool = false,

    /// Map a paint-space pixel to the CSS gradient parameter.
    pub fn sample(self: Gradient, x: f32, y: f32, width: f32, height: f32) [4]u8 {
        const dx = x - self.center_x * width;
        const dy = y - self.center_y * height;
        const radians = self.angle_deg * std.math.pi / 180;
        const t: f32 = switch (self.kind) {
            .linear => blk: {
                const sx = @sin(radians);
                const sy = -@cos(radians);
                const len = @abs(sx) * width + @abs(sy) * height;
                break :blk if (len > 0) 0.5 + ((x - width / 2) * sx + (y - height / 2) * sy) / len else 0;
            },
            .conic => blk: {
                var angle = std.math.atan2(dx, -dy) - radians;
                angle = @mod(angle, 2 * std.math.pi);
                break :blk angle / (2 * std.math.pi);
            },
            .radial => blk: {
                var rx = if (self.closest_side) @min(self.center_x, 1 - self.center_x) * width else @max(self.center_x, 1 - self.center_x) * width;
                var ry = if (self.closest_side) @min(self.center_y, 1 - self.center_y) * height else @max(self.center_y, 1 - self.center_y) * height;
                if (self.circle) {
                    const r = if (self.closest_side) @min(rx, ry) else @sqrt(rx * rx + ry * ry);
                    rx = r;
                    ry = r;
                } else if (!self.closest_side) {
                    rx *= @sqrt(@as(f32, 2));
                    ry *= @sqrt(@as(f32, 2));
                }
                break :blk @sqrt((dx / @max(0.0001, rx)) * (dx / @max(0.0001, rx)) + (dy / @max(0.0001, ry)) * (dy / @max(0.0001, ry)));
            },
        };
        return self.evaluate(t);
    }
    /// Evaluates the gradient color at parameter t (0.0 to 1.0).
    pub fn evaluate(self: Gradient, t_in: f32) [4]u8 {
        if (self.stops.len == 0) return .{ 0, 0, 0, 255 };
        if (self.stops.len == 1) return self.stops[0].color;
        const t = std.math.clamp(t_in, 0.0, 1.0);

        if (t <= (self.stops[0].position orelse 0.0)) return self.stops[0].color;
        const last = self.stops[self.stops.len - 1];
        if (t >= (last.position orelse 1.0)) return last.color;

        for (0..self.stops.len - 1) |i| {
            const s0 = self.stops[i];
            const s1 = self.stops[i + 1];
            const p0 = s0.position orelse 0.0;
            const p1 = s1.position orelse 1.0;
            if (t >= p0 and t <= p1) {
                const span = p1 - p0;
                const factor = if (span <= 0.0001) 0.0 else (t - p0) / span;
                return .{
                    @intFromFloat(@as(f32, @floatFromInt(s0.color[0])) * (1.0 - factor) + @as(f32, @floatFromInt(s1.color[0])) * factor),
                    @intFromFloat(@as(f32, @floatFromInt(s0.color[1])) * (1.0 - factor) + @as(f32, @floatFromInt(s1.color[1])) * factor),
                    @intFromFloat(@as(f32, @floatFromInt(s0.color[2])) * (1.0 - factor) + @as(f32, @floatFromInt(s1.color[2])) * factor),
                    @intFromFloat(@as(f32, @floatFromInt(s0.color[3])) * (1.0 - factor) + @as(f32, @floatFromInt(s1.color[3])) * factor),
                };
            }
        }
        return last.color;
    }
};

pub fn parseColor(str_in: []const u8) ?[4]u8 {
    const str = std.mem.trim(u8, str_in, " \t\r\n");
    if (str.len == 0) return null;
    if (std.mem.eql(u8, str, "transparent")) return .{ 0, 0, 0, 0 };
    if (std.mem.eql(u8, str, "black")) return .{ 0, 0, 0, 255 };
    if (std.mem.eql(u8, str, "white")) return .{ 255, 255, 255, 255 };
    if (std.mem.eql(u8, str, "red")) return .{ 255, 0, 0, 255 };
    if (std.mem.eql(u8, str, "green")) return .{ 0, 128, 0, 255 };
    if (std.mem.eql(u8, str, "blue")) return .{ 0, 0, 255, 255 };
    if (std.mem.eql(u8, str, "yellow")) return .{ 255, 255, 0, 255 };
    if (std.mem.eql(u8, str, "gray") or std.mem.eql(u8, str, "grey")) return .{ 128, 128, 128, 255 };

    if (str[0] == '#') {
        if (str.len == 4) {
            // #rgb
            const r = std.fmt.parseInt(u8, str[1..2], 16) catch return null;
            const g = std.fmt.parseInt(u8, str[2..3], 16) catch return null;
            const b = std.fmt.parseInt(u8, str[3..4], 16) catch return null;
            return .{ r * 17, g * 17, b * 17, 255 };
        } else if (str.len == 5) {
            // #rgba
            const r = std.fmt.parseInt(u8, str[1..2], 16) catch return null;
            const g = std.fmt.parseInt(u8, str[2..3], 16) catch return null;
            const b = std.fmt.parseInt(u8, str[3..4], 16) catch return null;
            const a = std.fmt.parseInt(u8, str[4..5], 16) catch return null;
            return .{ r * 17, g * 17, b * 17, a * 17 };
        } else if (str.len == 7) {
            // #rrggbb
            const rgb = std.fmt.parseInt(u32, str[1..7], 16) catch return null;
            return .{
                @intCast((rgb >> 16) & 255),
                @intCast((rgb >> 8) & 255),
                @intCast(rgb & 255),
                255,
            };
        } else if (str.len == 9) {
            // #rrggbbaa
            const rgba = std.fmt.parseInt(u32, str[1..9], 16) catch return null;
            return .{
                @intCast((rgba >> 24) & 255),
                @intCast((rgba >> 16) & 255),
                @intCast((rgba >> 8) & 255),
                @intCast(rgba & 255),
            };
        }
    }

    if (std.mem.startsWith(u8, str, "rgb(") or std.mem.startsWith(u8, str, "rgba(")) {
        const start = (std.mem.indexOfScalar(u8, str, '(') orelse return null) + 1;
        const end = std.mem.lastIndexOfScalar(u8, str, ')') orelse return null;
        if (start >= end) return null;
        const inner = str[start..end];
        var it = std.mem.tokenizeAny(u8, inner, ", / \t");
        const r_str = it.next() orelse return null;
        const g_str = it.next() orelse return null;
        const b_str = it.next() orelse return null;
        const a_str = it.next();

        const r = std.fmt.parseInt(u8, std.mem.trim(u8, r_str, " "), 10) catch return null;
        const g = std.fmt.parseInt(u8, std.mem.trim(u8, g_str, " "), 10) catch return null;
        const b = std.fmt.parseInt(u8, std.mem.trim(u8, b_str, " "), 10) catch return null;
        var a: u8 = 255;
        if (a_str) |as| {
            const astr = std.mem.trim(u8, as, " ");
            if (std.mem.endsWith(u8, astr, "%")) {
                const pct = std.fmt.parseFloat(f32, astr[0 .. astr.len - 1]) catch 100;
                a = @intFromFloat(std.math.clamp(pct * 2.55, 0, 255));
            } else {
                const alpha_f = std.fmt.parseFloat(f32, astr) catch 1.0;
                a = @intFromFloat(std.math.clamp(alpha_f * 255.0, 0, 255));
            }
        }
        return .{ r, g, b, a };
    }

    return null;
}

/// Parses linear-gradient, radial-gradient, or conic-gradient CSS string.
pub fn parseGradient(allocator: std.mem.Allocator, css_in: []const u8) !?Gradient {
    const css = std.mem.trim(u8, css_in, " \t\r\n");
    if (css.len == 0) return null;

    var kind: GradientKind = undefined;
    var prefix_len: usize = 0;
    if (std.mem.startsWith(u8, css, "linear-gradient")) {
        kind = .linear;
        prefix_len = 15;
    } else if (std.mem.startsWith(u8, css, "radial-gradient")) {
        kind = .radial;
        prefix_len = 15;
    } else if (std.mem.startsWith(u8, css, "conic-gradient")) {
        kind = .conic;
        prefix_len = 14;
    } else {
        return null;
    }

    const start_paren = std.mem.indexOfScalar(u8, css[prefix_len..], '(') orelse return null;
    const end_paren = std.mem.lastIndexOfScalar(u8, css, ')') orelse return null;
    const body = css[prefix_len + start_paren + 1 .. end_paren];

    // Split by comma outside parentheses
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);

    var depth: usize = 0;
    var seg_start: usize = 0;
    for (body, 0..) |c, idx| {
        if (c == '(') depth += 1;
        if (c == ')') {
            if (depth > 0) depth -= 1;
        }
        if (c == ',' and depth == 0) {
            try parts.append(allocator, std.mem.trim(u8, body[seg_start..idx], " \t\r\n"));
            seg_start = idx + 1;
        }
    }
    if (seg_start < body.len) {
        try parts.append(allocator, std.mem.trim(u8, body[seg_start..], " \t\r\n"));
    }

    if (parts.items.len == 0) return null;

    var angle_deg: f32 = if (kind == .linear) 180.0 else 0.0;
    var center_x: f32 = 0.5;
    var center_y: f32 = 0.5;
    var stop_start_idx: usize = 0;

    // Check if the first argument is a direction, angle, or position
    const first = parts.items[0];
    var is_config = false;

    if (kind == .linear) {
        if (std.mem.startsWith(u8, first, "to ")) {
            is_config = true;
            if (std.mem.eql(u8, first, "to top")) angle_deg = 0.0;
            if (std.mem.eql(u8, first, "to right")) angle_deg = 90.0;
            if (std.mem.eql(u8, first, "to bottom")) angle_deg = 180.0;
            if (std.mem.eql(u8, first, "to left")) angle_deg = 270.0;
            if (std.mem.eql(u8, first, "to top right") or std.mem.eql(u8, first, "to right top")) angle_deg = 45.0;
            if (std.mem.eql(u8, first, "to bottom right") or std.mem.eql(u8, first, "to right bottom")) angle_deg = 135.0;
            if (std.mem.eql(u8, first, "to bottom left") or std.mem.eql(u8, first, "to left bottom")) angle_deg = 225.0;
            if (std.mem.eql(u8, first, "to top left") or std.mem.eql(u8, first, "to left top")) angle_deg = 315.0;
        } else if (std.mem.endsWith(u8, first, "deg")) {
            if (std.fmt.parseFloat(f32, first[0 .. first.len - 3])) |a| {
                angle_deg = a;
                is_config = true;
            } else |_| {}
        } else if (std.mem.endsWith(u8, first, "rad")) {
            if (std.fmt.parseFloat(f32, first[0 .. first.len - 3])) |r| {
                angle_deg = r * (180.0 / std.math.pi);
                is_config = true;
            } else |_| {}
        } else if (std.mem.endsWith(u8, first, "turn")) {
            if (std.fmt.parseFloat(f32, first[0 .. first.len - 4])) |turn| {
                angle_deg = turn * 360.0;
                is_config = true;
            } else |_| {}
        }
    } else if (kind == .radial) {
        if (std.mem.indexOf(u8, first, "at ") != null or std.mem.eql(u8, first, "circle") or std.mem.eql(u8, first, "ellipse")) {
            is_config = true;
            if (std.mem.indexOf(u8, first, "at ")) |at_idx| {
                const pos_str = std.mem.trim(u8, first[at_idx + 3 ..], " ");
                var pos_it = std.mem.tokenizeAny(u8, pos_str, " ");
                if (pos_it.next()) |px| {
                    if (std.mem.endsWith(u8, px, "%")) {
                        center_x = (std.fmt.parseFloat(f32, px[0 .. px.len - 1]) catch 50) / 100.0;
                    }
                }
                if (pos_it.next()) |py| {
                    if (std.mem.endsWith(u8, py, "%")) {
                        center_y = (std.fmt.parseFloat(f32, py[0 .. py.len - 1]) catch 50) / 100.0;
                    }
                }
            }
        }
    } else if (kind == .conic) {
        if (std.mem.startsWith(u8, first, "from ") or std.mem.indexOf(u8, first, "at ") != null) {
            is_config = true;
            if (std.mem.startsWith(u8, first, "from ")) {
                var it = std.mem.tokenizeAny(u8, first[5..], " ");
                if (it.next()) |angle_str| {
                    if (std.mem.endsWith(u8, angle_str, "deg")) {
                        angle_deg = std.fmt.parseFloat(f32, angle_str[0 .. angle_str.len - 3]) catch 0;
                    } else if (std.mem.endsWith(u8, angle_str, "turn")) {
                        angle_deg = (std.fmt.parseFloat(f32, angle_str[0 .. angle_str.len - 4]) catch 0) * 360.0;
                    }
                }
            }
            if (std.mem.indexOf(u8, first, "at ")) |at_idx| {
                const pos_str = std.mem.trim(u8, first[at_idx + 3 ..], " ");
                var pos_it = std.mem.tokenizeAny(u8, pos_str, " ");
                if (pos_it.next()) |px| {
                    if (std.mem.endsWith(u8, px, "%")) {
                        center_x = (std.fmt.parseFloat(f32, px[0 .. px.len - 1]) catch 50) / 100.0;
                    }
                }
                if (pos_it.next()) |py| {
                    if (std.mem.endsWith(u8, py, "%")) {
                        center_y = (std.fmt.parseFloat(f32, py[0 .. py.len - 1]) catch 50) / 100.0;
                    }
                }
            }
        }
    }

    if (is_config) stop_start_idx = 1;

    var raw_stops: std.ArrayList(ColorStop) = .empty;
    defer raw_stops.deinit(allocator);

    for (parts.items[stop_start_idx..]) |stop_str| {
        var it = std.mem.tokenizeAny(u8, stop_str, " \t");
        const color_part = it.next() orelse continue;
        var full_color = color_part;
        // Check if rgb/rgba function had internal tokens
        if (std.mem.startsWith(u8, color_part, "rgb(") or std.mem.startsWith(u8, color_part, "rgba(")) {
            while (!std.mem.endsWith(u8, full_color, ")")) {
                const next_tok = it.next() orelse break;
                // re-construct
                full_color = stop_str[0 .. std.mem.indexOf(u8, stop_str, next_tok).? + next_tok.len];
            }
        }

        const col = parseColor(full_color) orelse continue;
        var pos: ?f32 = null;
        if (it.next()) |pos_tok| {
            if (std.mem.endsWith(u8, pos_tok, "%")) {
                pos = (std.fmt.parseFloat(f32, pos_tok[0 .. pos_tok.len - 1]) catch 0) / 100.0;
            } else if (std.mem.endsWith(u8, pos_tok, "deg")) {
                pos = (std.fmt.parseFloat(f32, pos_tok[0 .. pos_tok.len - 3]) catch 0) / 360.0;
            } else if (std.mem.endsWith(u8, pos_tok, "turn")) {
                pos = std.fmt.parseFloat(f32, pos_tok[0 .. pos_tok.len - 4]) catch 0;
            }
        }
        try raw_stops.append(allocator, .{ .color = col, .position = pos });
    }

    if (raw_stops.items.len == 0) return null;

    // Distribute missing positions
    const count = raw_stops.items.len;
    if (raw_stops.items[0].position == null) raw_stops.items[0].position = 0.0;
    if (raw_stops.items[count - 1].position == null) raw_stops.items[count - 1].position = 1.0;

    var start_i: usize = 0;
    while (start_i < count) {
        if (raw_stops.items[start_i].position != null) {
            start_i += 1;
            continue;
        }
        var end_i = start_i;
        while (end_i < count and raw_stops.items[end_i].position == null) : (end_i += 1) {}
        const prev_pos = raw_stops.items[start_i - 1].position orelse 0.0;
        const next_pos = if (end_i < count) (raw_stops.items[end_i].position orelse 1.0) else 1.0;
        const span = next_pos - prev_pos;
        const steps = @as(f32, @floatFromInt(end_i - start_i + 1));
        for (start_i..end_i) |k| {
            raw_stops.items[k].position = prev_pos + span * (@as(f32, @floatFromInt(k - start_i + 1)) / steps);
        }
        start_i = end_i;
    }

    var previous: f32 = -std.math.inf(f32);
    for (raw_stops.items) |*stop| {
        stop.position = @max(previous, stop.position orelse 0);
        previous = stop.position.?;
    }
    const stops_slice = try allocator.dupe(ColorStop, raw_stops.items);
    return .{
        .kind = kind,
        .angle_deg = angle_deg,
        .center_x = center_x,
        .center_y = center_y,
        .stops = stops_slice,
        .circle = std.mem.indexOf(u8, first, "circle") != null,
        .closest_side = std.mem.indexOf(u8, first, "closest-side") != null,
    };
}
