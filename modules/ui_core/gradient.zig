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
    repeating: bool = false,

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
        var t = t_in;
        if (self.repeating) {
            const start = self.stops[0].position orelse 0;
            const finish = self.stops[self.stops.len - 1].position orelse 1;
            if (finish > start) t = start + @mod(t - start, finish - start) else return self.stops[self.stops.len - 1].color;
        }

        if (t <= (self.stops[0].position orelse 0.0)) return self.stops[0].color;
        const last = self.stops[self.stops.len - 1];
        if (t >= (last.position orelse 1.0)) return last.color;

        for (0..self.stops.len - 1) |i| {
            const s0 = self.stops[i];
            const s1 = self.stops[i + 1];
            const p0 = s0.position orelse 0.0;
            const p1 = s1.position orelse 1.0;
            if (t >= p0 and t <= p1) {
                if (std.mem.eql(u8, &s0.color, &s1.color)) return s0.color;
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

pub const parseColor = @import("colors.zig").parseColor;

const colors = @import("colors.zig");
const whitespace = " \t\r\n\x0c";

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn starts(a: []const u8, b: []const u8) bool {
    return a.len >= b.len and eql(a[0..b.len], b);
}

fn finiteFloat(value: f64) ?f32 {
    if (!std.math.isFinite(value) or @abs(value) > std.math.floatMax(f32)) return null;
    return @floatCast(value);
}

const StopPosition = struct {
    normalized: f32,
    length: bool = false,
};

fn stopPosition(token: []const u8, kind: GradientKind) ?StopPosition {
    if (std.mem.endsWith(u8, token, "%")) return .{ .normalized = finiteFloat((colors.number(token[0 .. token.len - 1]) orelse return null) / 100) orelse return null };
    if (kind == .conic) {
        if (colors.angle(token, false)) |angle| return .{ .normalized = finiteFloat(angle / 360) orelse return null };
    } else {
        // Lengths are meaningful only with a paint size. Constant-color images
        // do not need that size; other length-stop gradients are rejected below.
        for ([_][]const u8{ "px", "em", "rem", "ex", "rex", "ch", "rch", "cap", "rcap", "ic", "ric", "lh", "rlh", "vw", "vh", "vi", "vb", "vmin", "vmax", "svw", "svh", "svi", "svb", "svmin", "svmax", "lvw", "lvh", "lvi", "lvb", "lvmin", "lvmax", "dvw", "dvh", "dvi", "dvb", "dvmin", "dvmax", "cqw", "cqh", "cqi", "cqb", "cqmin", "cqmax", "cm", "mm", "q", "in", "pt", "pc" }) |unit| {
            if (token.len > unit.len and eql(token[token.len - unit.len ..], unit)) {
                _ = colors.number(token[0 .. token.len - unit.len]) orelse continue;
                return .{ .normalized = 0, .length = true };
            }
        }
    }
    if (colors.number(token)) |n| if (n == 0) return .{ .normalized = 0 };
    return null;
}

fn positionValue(token: []const u8) ?f32 {
    if (eql(token, "center")) return 0.5;
    if (eql(token, "left") or eql(token, "top")) return 0;
    if (eql(token, "right") or eql(token, "bottom")) return 1;
    if (std.mem.endsWith(u8, token, "%")) return finiteFloat((colors.number(token[0 .. token.len - 1]) orelse return null) / 100);
    if (colors.number(token)) |n| if (n == 0) return 0;
    return null;
}

fn horizontal(token: []const u8) bool {
    return eql(token, "left") or eql(token, "right");
}

fn vertical(token: []const u8) bool {
    return eql(token, "top") or eql(token, "bottom");
}

fn parseCenter(tokens: []const []const u8, x: *f32, y: *f32) bool {
    if (tokens.len == 0 or tokens.len > 2) return false;
    if (tokens.len == 1) {
        const p = positionValue(tokens[0]) orelse return false;
        if (vertical(tokens[0])) y.* = p else x.* = p;
        return true;
    }
    const a = tokens[0];
    const b = tokens[1];
    if (vertical(a) or horizontal(b)) {
        if ((!vertical(a) and !eql(a, "center")) or (!horizontal(b) and !eql(b, "center"))) return false;
        x.* = positionValue(b) orelse return false;
        y.* = positionValue(a) orelse return false;
    } else {
        if (vertical(a) or horizontal(b)) return false;
        x.* = positionValue(a) orelse return false;
        y.* = positionValue(b) orelse return false;
    }
    return true;
}

fn parseConfiguration(text: []const u8, gradient: *Gradient) bool {
    var tokens: [12][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, text, whitespace);
    while (it.next()) |token| {
        if (count == tokens.len) return false;
        tokens[count] = token;
        count += 1;
    }
    if (count == 0) return false;
    const args = tokens[0..count];
    if (gradient.kind == .linear) {
        if (count == 1) {
            gradient.angle_deg = finiteFloat(colors.angle(args[0], false) orelse return false) orelse return false;
            return true;
        }
        if (!eql(args[0], "to") or count > 3) return false;
        var h: i8 = 0;
        var v: i8 = 0;
        for (args[1..]) |token| {
            if (horizontal(token)) {
                if (h != 0) return false;
                h = if (eql(token, "right")) 1 else -1;
            } else if (vertical(token)) {
                if (v != 0) return false;
                v = if (eql(token, "bottom")) 1 else -1;
            } else return false;
        }
        gradient.angle_deg = if (h == 0) (if (v == -1) @as(f32, 0) else 180) else if (v == 0) (if (h == 1) @as(f32, 90) else 270) else if (h == 1) (if (v == -1) @as(f32, 45) else 135) else (if (v == -1) @as(f32, 315) else 225);
        return true;
    }
    var index: usize = 0;
    if (gradient.kind == .conic) {
        if (eql(args[0], "from")) {
            if (count < 2) return false;
            gradient.angle_deg = finiteFloat(colors.angle(args[1], false) orelse return false) orelse return false;
            index = 2;
        }
    } else {
        var shape = false;
        var size = false;
        while (index < count and !eql(args[index], "at")) : (index += 1) {
            const token = args[index];
            if (eql(token, "circle") or eql(token, "ellipse")) {
                if (shape) return false;
                shape = true;
                gradient.circle = eql(token, "circle");
            } else if (eql(token, "closest-side") or eql(token, "farthest-corner")) {
                if (size) return false;
                size = true;
                gradient.closest_side = eql(token, "closest-side");
            } else return false;
        }
    }
    if (index < count) {
        if (!eql(args[index], "at")) return false;
        return parseCenter(args[index + 1 ..], &gradient.center_x, &gradient.center_y);
    }
    return index > 0;
}

// Constant-color images have no observable gradient geometry, but their prelude
// must still satisfy the position/radius/interpolation grammar.
fn constantPosition(tokens: []const []const u8) bool {
    if (tokens.len == 0 or tokens.len > 4) return false;
    if (tokens.len <= 2) {
        if (tokens.len == 2 and ((horizontal(tokens[0]) and horizontal(tokens[1])) or (vertical(tokens[0]) and vertical(tokens[1])))) return false;
        for (tokens) |t| {
            if (eql(t, "center") or horizontal(t) or vertical(t)) continue;
            const q = @import("sizing.zig").resolveValue(t, .{}) catch return false;
            if (q.dimension != .length and !(q.dimension == .number and q.value != null and q.value.? == 0)) return false;
        }
        return true;
    }
    var h = false;
    var v = false;
    var i: usize = 0;
    while (i < tokens.len) {
        const t = tokens[i];
        if (horizontal(t)) {
            if (h) return false;
            h = true;
        } else if (vertical(t)) {
            if (v) return false;
            v = true;
        } else if (eql(t, "center")) {
            if (!h) h = true else if (!v) v = true else return false;
            i += 1;
            continue;
        } else return false;
        i += 1;
        if (i < tokens.len and !horizontal(tokens[i]) and !vertical(tokens[i]) and !eql(tokens[i], "center")) {
            const q = @import("sizing.zig").resolveValue(tokens[i], .{}) catch return false;
            if (q.dimension != .length and !(q.dimension == .number and q.value != null and q.value.? == 0)) return false;
            i += 1;
        }
    }
    return h and v;
}
fn constantConfiguration(text: []const u8, kind: GradientKind) bool {
    var storage: [24][]const u8 = undefined;
    var count: usize = 0;
    var tokens = @import("css_syntax.zig").Tokens{ .input = text, .separators = whitespace };
    while (tokens.next()) |token| {
        if (count == storage.len) return false;
        storage[count] = token;
        count += 1;
    }
    if (count == 0) return false;
    var filtered: [24][]const u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    var interpolation = false;
    while (i < count) {
        if (eql(storage[i], "in")) {
            if (interpolation or i + 1 >= count) return false;
            interpolation = true;
            i += 1;
            const space = storage[i];
            const polar = eql(space, "hsl") or eql(space, "hwb") or eql(space, "lch") or eql(space, "oklch");
            const rectangular = eql(space, "srgb") or eql(space, "srgb-linear") or eql(space, "display-p3") or eql(space, "a98-rgb") or eql(space, "prophoto-rgb") or eql(space, "rec2020") or eql(space, "lab") or eql(space, "oklab") or eql(space, "xyz") or eql(space, "xyz-d50") or eql(space, "xyz-d65");
            if (!polar and !rectangular) return false;
            i += 1;
            if (i < count and (eql(storage[i], "shorter") or eql(storage[i], "longer") or eql(storage[i], "increasing") or eql(storage[i], "decreasing"))) {
                if (!polar or i + 1 >= count or !eql(storage[i + 1], "hue")) return false;
                i += 2;
            }
        } else {
            filtered[n] = storage[i];
            n += 1;
            i += 1;
        }
    }
    const args = filtered[0..n];
    if (n == 0) return interpolation;
    if (kind == .linear) {
        if (n == 1) {
            const q = @import("sizing.zig").resolveValue(args[0], .{}) catch return false;
            return q.dimension == .angle or (q.dimension == .number and q.value != null and q.value.? == 0);
        }
        if (!eql(args[0], "to") or n > 3) return false;
        if (n == 2) return horizontal(args[1]) or vertical(args[1]);
        return (horizontal(args[1]) and vertical(args[2])) or (vertical(args[1]) and horizontal(args[2]));
    }
    i = 0;
    if (kind == .conic) {
        if (eql(args[0], "from")) {
            if (n < 2) return false;
            const q = @import("sizing.zig").resolveValue(args[1], .{}) catch return false;
            if (q.dimension != .angle and !(q.dimension == .number and q.value != null and q.value.? == 0)) return false;
            i = 2;
        }
    } else {
        var circle: ?bool = null;
        var keyword = false;
        var radii: usize = 0;
        var percentage = false;
        while (i < n and !eql(args[i], "at")) : (i += 1) {
            const t = args[i];
            if (eql(t, "circle") or eql(t, "ellipse")) {
                if (circle != null) return false;
                circle = eql(t, "circle");
            } else if (eql(t, "closest-side") or eql(t, "closest-corner") or eql(t, "farthest-side") or eql(t, "farthest-corner")) {
                if (keyword or radii > 0) return false;
                keyword = true;
            } else {
                if (keyword or radii == 2) return false;
                const q = @import("sizing.zig").resolveValue(t, .{}) catch return false;
                if (q.dimension != .length and !(q.dimension == .number and q.value != null and q.value.? == 0)) return false;
                if (q.value) |v| if (v < 0) return false;
                percentage = percentage or std.mem.indexOfScalar(u8, t, '%') != null;
                radii += 1;
            }
        }
        if (radii == 1 and (percentage or circle == false)) return false;
        if (radii == 2 and circle == true) return false;
    }
    if (i < n) {
        if (!eql(args[i], "at")) return false;
        return constantPosition(args[i + 1 ..]);
    }
    return i > 0;
}

/// Parse all six gradient functions, including the CSS Images 4 single-color
/// stop form and double-position stops. The caller owns the returned stops.
pub fn parseGradient(allocator: std.mem.Allocator, css_in: []const u8) !?Gradient {
    var css = std.mem.trim(u8, css_in, whitespace);
    const repeating = starts(css, "repeating-");
    if (repeating) css = css[10..];
    const open = std.mem.indexOfScalar(u8, css, '(') orelse return null;
    if (css.len == 0 or css[css.len - 1] != ')') return null;
    const name = css[0..open];
    const kind: GradientKind = if (eql(name, "linear-gradient")) .linear else if (eql(name, "radial-gradient")) .radial else if (eql(name, "conic-gradient")) .conic else return null;
    const body = css[open + 1 .. css.len - 1];
    var gradient = Gradient{ .kind = kind, .repeating = repeating, .angle_deg = if (kind == .linear) 180 else 0, .stops = &.{} };

    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);
    var depth: usize = 0;
    var start: usize = 0;
    for (body, 0..) |c, i| {
        switch (c) {
            '(' => depth += 1,
            ')' => {
                if (depth == 0) return null;
                depth -= 1;
            },
            ',' => if (depth == 0) {
                const part = std.mem.trim(u8, body[start..i], whitespace);
                if (part.len == 0) return null;
                try parts.append(allocator, part);
                start = i + 1;
            },
            else => {},
        }
    }
    if (depth != 0) return null;
    const last = std.mem.trim(u8, body[start..], whitespace);
    if (last.len == 0) return null;
    try parts.append(allocator, last);

    var raw_stops: std.ArrayList(ColorStop) = .empty;
    defer raw_stops.deinit(allocator);
    var lengths = false;
    var pending_configuration: ?[]const u8 = null;
    for (parts.items, 0..) |part, part_index| {
        // Find the end of the color token without splitting its function body.
        var color_end: usize = 0;
        depth = 0;
        while (color_end < part.len) : (color_end += 1) {
            const c = part[color_end];
            if (c == '(') depth += 1;
            if (c == ')') {
                if (depth == 0) return null;
                depth -= 1;
            }
            if (depth == 0 and std.mem.indexOfScalar(u8, whitespace, c) != null) break;
        }
        const color = parseColor(part[0..color_end]) orelse {
            if (part_index == 0 and parts.items.len > 1) {
                if (parseConfiguration(part, &gradient)) continue;
                pending_configuration = part;
                continue;
            }
            return null;
        };
        var positions = std.mem.tokenizeAny(u8, part[color_end..], whitespace);
        var stop = ColorStop{ .color = color };
        if (positions.next()) |token| {
            const position = stopPosition(token, kind) orelse return null;
            stop.position = position.normalized;
            lengths = lengths or position.length;
        }
        try raw_stops.append(allocator, stop);
        if (positions.next()) |token| {
            const position = stopPosition(token, kind) orelse return null;
            lengths = lengths or position.length;
            try raw_stops.append(allocator, .{ .color = color, .position = position.normalized });
        }
        if (positions.next() != null) return null;
    }
    if (raw_stops.items.len == 0) return null;
    if (pending_configuration) |configuration| {
        for (raw_stops.items[1..]) |stop| if (!std.mem.eql(u8, &stop.color, &raw_stops.items[0].color)) return null;
        if (!constantConfiguration(configuration, kind)) return null;
    }
    if (lengths) {
        for (raw_stops.items[1..]) |stop| if (!std.mem.eql(u8, &stop.color, &raw_stops.items[0].color)) return null;
    }
    const count = raw_stops.items.len;
    if (raw_stops.items[0].position == null) raw_stops.items[0].position = 0;
    if (raw_stops.items[count - 1].position == null) raw_stops.items[count - 1].position = 1;
    // Clamp specified stops first, then interpolate runs of omitted positions.
    var previous: f32 = -std.math.inf(f32);
    for (raw_stops.items) |*stop| {
        if (stop.position) |p| {
            stop.position = @max(previous, p);
            previous = stop.position.?;
        }
    }
    var i: usize = 1;
    while (i < count) {
        if (raw_stops.items[i].position != null) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < count and raw_stops.items[end].position == null) : (end += 1) {}
        const lo = raw_stops.items[i - 1].position.?;
        const hi = raw_stops.items[end].position.?;
        for (i..end) |j| raw_stops.items[j].position = lo + (hi - lo) * @as(f32, @floatFromInt(j - i + 1)) / @as(f32, @floatFromInt(end - i + 1));
        i = end;
    }
    gradient.stops = try allocator.dupe(ColorStop, raw_stops.items);
    return gradient;
}
