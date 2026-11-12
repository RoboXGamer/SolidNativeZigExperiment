//! Retained CSS transition state; the host schedules frames only while active.
const std = @import("std");
const ui = @import("root.zig");
const anim = @import("animation.zig");
const Tokens = @import("css_syntax.zig").Tokens;
pub const Value = union(enum) { number: f32, color: [4]u8, matrix: ui.transform.Matrix2D, discrete: []const u8 };
const Config = struct {
    duration: f32 = 0,
    delay: f32 = 0,
    curve: anim.Timing = .{ .bezier = anim.CubicBezier.ease },
    behavior: enum { normal, allow_discrete } = .normal,

    fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        self.curve.deinit(allocator);
    }
};
const Track = struct {
    id: u32,
    field: []const u8,
    from: Value,
    to: Value,
    start: f64,
    config: Config,
    fn sample(t: Track, now: f64) Value {
        const elapsed = @as(f32, @floatCast(now - t.start)) - t.config.delay;
        const p = if (elapsed < 0) t.config.curve.solveBefore(0, true) else if (elapsed >= t.config.duration or t.config.duration <= 0) @as(f32, 1) else t.config.curve.solveBefore(elapsed / t.config.duration, false);
        return switch (t.from) {
            .number => |v| .{ .number = anim.interpolateNumber(v, t.to.number, p) },
            .color => |v| .{ .color = anim.interpolateColor(v, t.to.color, p) },
            .matrix => |v| .{ .matrix = anim.interpolateMatrix(v, t.to.matrix, p) },
            .discrete => |v| if (p < 0.5) .{ .discrete = v } else .{ .discrete = t.to.discrete },
        };
    }
};
fn matches(css: []const u8, field: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(css, "none")) return false;
    if (std.ascii.eqlIgnoreCase(css, "all")) return true;
    var i: usize = 0;
    for (css) |c| {
        if (c == '-') continue;
        if (i >= field.len or std.ascii.toLower(c) != std.ascii.toLower(field[i])) return false;
        i += 1;
    }
    return i == field.len;
}
fn time(s: []const u8) ?f32 {
    if (s.len >= 2 and std.ascii.eqlIgnoreCase(s[s.len - 2 ..], "ms")) return (@import("easing.zig").parseNumberStrict(s[0 .. s.len - 2]) catch return null) / 1000;
    if (s.len >= 1 and std.ascii.eqlIgnoreCase(s[s.len - 1 ..], "s")) return @import("easing.zig").parseNumberStrict(s[0 .. s.len - 1]) catch null;
    return null;
}
// A malformed shorthand invalidates the entire declaration, including earlier
// layers. The selected Config owns its curve independently of the style arena.
fn config(allocator: std.mem.Allocator, style: ui.Style, field: []const u8) !Config {
    var result = Config{};
    errdefer result.deinit(allocator);
    if (style.transition.len > 0) {
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, style.transition, " \t\r\n"), "none")) return result;
        var layers = TransitionTokens{ .input = style.transition, .separator = .comma };
        while (try layers.next()) |layer| {
            var tokens = TransitionTokens{ .input = layer, .separator = .space };
            var property: []const u8 = "all";
            var has_property = false;
            var has_curve = false;
            var c = Config{};
            defer c.deinit(allocator);
            var times: usize = 0;
            while (try tokens.next()) |token| {
                if (std.ascii.eqlIgnoreCase(token, "allow-discrete")) {
                    c.behavior = .allow_discrete;
                } else if (std.ascii.eqlIgnoreCase(token, "normal")) {
                    c.behavior = .normal;
                } else if (std.ascii.eqlIgnoreCase(token, "none")) {
                    property = "none";
                    has_property = true;
                } else if (time(token)) |v| {
                    if (!std.math.isFinite(v) or times == 2 or (times == 0 and v < 0)) return error.InvalidTransition;
                    if (times == 0) c.duration = v else c.delay = v;
                    times += 1;
                } else {
                    const curve = anim.Timing.parseStrict(allocator, token) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        error.InvalidTimingFunction => {
                            if (has_property or !propertyIdent(token)) return error.InvalidTransition;
                            property = token;
                            has_property = true;
                            continue;
                        },
                    };
                    if (has_curve) {
                        var duplicate = curve;
                        duplicate.deinit(allocator);
                        return error.InvalidTransition;
                    }
                    c.curve = curve;
                    has_curve = true;
                }
            }
            if (matches(property, field)) {
                result.deinit(allocator);
                result = c;
                c = .{};
            }
        }
    } else {
        if (std.ascii.eqlIgnoreCase(style.transitionProperty, "none")) return result;
        var properties = Tokens{ .input = style.transitionProperty, .separators = "," };
        while (properties.next()) |property| if (matches(property, field)) {
            if (!std.math.isFinite(style.transitionDuration) or !std.math.isFinite(style.transitionDelay) or style.transitionDuration < 0) return error.InvalidTransition;
            const curve = try anim.Timing.parseStrict(allocator, style.transitionTimingFunction);
            result.deinit(allocator);
            const behavior: @TypeOf(result.behavior) = if (std.ascii.eqlIgnoreCase(style.transitionBehavior, "allow-discrete")) .allow_discrete else .normal;
            result = .{ .duration = style.transitionDuration, .delay = style.transitionDelay, .curve = curve, .behavior = behavior };
        };
    }
    return result;
}

fn propertyIdent(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value, 0..) |c, i| {
        if (std.ascii.isAlphabetic(c) or c == '-' or c == '_' or (i > 0 and std.ascii.isDigit(c))) continue;
        return false;
    }
    // Reserved easing words must never be reinterpreted as property names.
    return !std.ascii.eqlIgnoreCase(value, "initial") and !std.ascii.eqlIgnoreCase(value, "inherit") and !std.ascii.eqlIgnoreCase(value, "unset") and !std.ascii.eqlIgnoreCase(value, "revert") and !std.ascii.eqlIgnoreCase(value, "revert-layer") and !std.ascii.eqlIgnoreCase(value, "normal") and !std.ascii.eqlIgnoreCase(value, "allow-discrete");
}

// Balanced, comment-aware tokenization for shorthand layers and components.
// Unlike a delimiter tokenizer it preserves empty comma items as errors.
const TransitionTokens = struct {
    input: []const u8,
    separator: enum { comma, space },
    pos: usize = 0,
    after_comma: bool = false,

    fn skip(self: *TransitionTokens) !void {
        while (self.pos < self.input.len) {
            if (std.mem.indexOfScalar(u8, " \t\r\n\x0c", self.input[self.pos]) != null) {
                self.pos += 1;
            } else if (std.mem.startsWith(u8, self.input[self.pos..], "/*")) {
                const end = std.mem.indexOf(u8, self.input[self.pos + 2 ..], "*/") orelse return error.InvalidTransition;
                self.pos += end + 4;
            } else break;
        }
    }

    fn next(self: *TransitionTokens) !?[]const u8 {
        try self.skip();
        if (self.pos == self.input.len) {
            if (self.after_comma) return error.InvalidTransition;
            return null;
        }
        self.after_comma = false;
        const start = self.pos;
        var depth: usize = 0;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (std.mem.startsWith(u8, self.input[self.pos..], "/*")) {
                if (depth == 0 and self.separator == .space) break;
                const end = std.mem.indexOf(u8, self.input[self.pos + 2 ..], "*/") orelse return error.InvalidTransition;
                self.pos += end + 4;
                continue;
            }
            if (c == '(') depth += 1 else if (c == ')') {
                if (depth == 0) return error.InvalidTransition;
                depth -= 1;
            } else if (depth == 0) {
                if (self.separator == .comma and c == ',') break;
                if (self.separator == .space and std.mem.indexOfScalar(u8, " \t\r\n\x0c", c) != null) break;
            }
            self.pos += 1;
        }
        if (depth != 0 or self.pos == start) return error.InvalidTransition;
        const token = std.mem.trim(u8, self.input[start..self.pos], " \t\r\n\x0c");
        if (self.separator == .comma and self.pos < self.input.len) {
            self.pos += 1;
            self.after_comma = true;
        }
        return token;
    }
};
fn equal(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .number => |v| v == b.number,
        .color => |v| std.mem.eql(u8, &v, &b.color),
        .matrix => |v| std.meta.eql(v, b.matrix),
        .discrete => |v| std.mem.eql(u8, v, b.discrete),
    };
}
pub const Timeline = struct {
    allocator: std.mem.Allocator,
    tracks: std.ArrayList(Track) = .empty,
    pub fn init(a: std.mem.Allocator) Timeline {
        return .{ .allocator = a };
    }
    pub fn deinit(self: *Timeline) void {
        for (self.tracks.items) |*t| t.config.deinit(self.allocator);\
        self.tracks.deinit(self.allocator);
    }
    fn remove(self: *Timeline, index: usize) void {
        var removed = self.tracks.swapRemove(index);
        removed.config.deinit(self.allocator);
    }

    /// Cancel every retained transition for a node, releasing owned curve data.
    pub fn cancel(self: *Timeline, id: u32) void {
        var i = self.tracks.items.len;
        while (i > 0) {
            i -= 1;
            if (self.tracks.items[i].id == id) self.remove(i);
        }
    }
    pub fn active(self: *const Timeline) bool {
        return self.tracks.items.len > 0;
    }
    fn update(self: *Timeline, id: u32, field: []const u8, from: Value, to: Value, style: ui.Style, now: f64) !void {
        var c = config(self.allocator, style, field) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => Config{},
        };
        defer c.deinit(self.allocator);
        if (std.meta.activeTag(from) == .discrete and c.behavior != .allow_discrete) return;
        for (self.tracks.items, 0..) |*t, i| if (t.id == id and std.mem.eql(u8, t.field, field)) {
            if (equal(t.to, to) and c.duration > 0) return;
            const current = t.sample(now);
            if (c.duration <= 0 or equal(current, to)) {
                self.remove(i);
                return;
            }
            t.config.deinit(self.allocator);
            t.* = .{ .id = id, .field = field, .from = current, .to = to, .start = now, .config = c };
            c = .{};
            return;
        };
        if (c.duration <= 0 or equal(from, to)) return;
        try self.tracks.append(self.allocator, .{ .id = id, .field = field, .from = from, .to = to, .start = now, .config = c });
        c = .{};
    }
    pub fn retarget(self: *Timeline, old: *const ui.Scene, target: *const ui.Scene, now: f64) !void {
        var i = self.tracks.items.len;
        while (i > 0) {
            i -= 1;
            if (target.find(self.tracks.items[i].id) == null) self.remove(i);
        }
        for (target.items.items) |item| {
            const previous = old.find(item.node.id) orelse continue;
            const before = previous.node.style;
            const after = item.node.style;
            const info = @typeInfo(ui.Style).@"struct";
            inline for (info.field_names, info.field_types) |name, T| {
                if (comptime std.mem.startsWith(u8, name, "transition")) continue;
                if (T == f32) try self.update(item.node.id, name, .{ .number = @field(before, name) }, .{ .number = @field(after, name) }, after, now) else if (T == ?f32) {
                    if (@field(before, name) != null and @field(after, name) != null) {
                        try self.update(item.node.id, name, .{ .number = @field(before, name).? }, .{ .number = @field(after, name).? }, after, now);
                    } else {
                        var k = self.tracks.items.len;
                        while (k > 0) {
                            k -= 1;
                            const t = self.tracks.items[k];
                            if (t.id == item.node.id and std.mem.eql(u8, t.field, name)) self.remove(k);
                        }
                    }
                } else if (T == []const u8 and comptime std.mem.endsWith(u8, name, "Color")) {
                    if (ui.gradient.parseColor(@field(before, name))) |v| if (ui.gradient.parseColor(@field(after, name))) |next| try self.update(item.node.id, name, .{ .color = v }, .{ .color = next }, after, now);
                } else if (T == []const u8 and !comptime std.mem.endsWith(u8, name, "Color")) {
                    const before_str = @field(before, name);
                    const after_str = @field(after, name);
                    if (!std.mem.eql(u8, before_str, after_str)) {
                        try self.update(item.node.id, name, .{ .discrete = before_str }, .{ .discrete = after_str }, after, now);
                    }
                }
            }
            const from = ui.transform.parseTransformSized(before.transform, previous.bounds.width, previous.bounds.height) catch ui.transform.Matrix2D.identity;
            const to = ui.transform.parseTransformSized(after.transform, item.bounds.width, item.bounds.height) catch ui.transform.Matrix2D.identity;
            try self.update(item.node.id, "transform", .{ .matrix = from }, .{ .matrix = to }, after, now);
        }
    }
    fn applyNode(self: *Timeline, n: *ui.Node, a: std.mem.Allocator, now: f64) !void {
        for (self.tracks.items) |t| if (t.id == n.id) {
            const v = t.sample(now);
            switch (v) {
                .number => |number| {
                    const info = @typeInfo(ui.Style).@"struct";
                    inline for (info.field_names, info.field_types) |name, T| if (T == f32 or T == ?f32) {
                        if (std.mem.eql(u8, name, t.field)) {
                            @field(n.style, name) = number;
                            if (@hasField(ui.Style, name ++ "Css")) @field(n.style, name ++ "Css") = null;
                        }
                    };
                },
                .color => |c| {
                    const value = try std.fmt.allocPrint(a, "#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ c[0], c[1], c[2], c[3] });
                    inline for (@typeInfo(ui.Style).@"struct".field_names, @typeInfo(ui.Style).@"struct".field_types) |name, T| if (T == []const u8 and comptime std.mem.endsWith(u8, name, "Color")) {
                        if (std.mem.eql(u8, name, t.field)) @field(n.style, name) = value;
                    };
                },
                .matrix => |m| n.style.transform = try std.fmt.allocPrint(a, "matrix({d},{d},{d},{d},{d},{d})", .{ m.a, m.b, m.c, m.d, m.tx, m.ty }),
                .discrete => |s| {
                    inline for (@typeInfo(ui.Style).@"struct".field_names, @typeInfo(ui.Style).@"struct".field_types) |name, T| if (T == []const u8 and !comptime std.mem.endsWith(u8, name, "Color")) {
                        if (std.mem.eql(u8, name, t.field)) @field(n.style, name) = s;
                    };
                },
            }
        };
        for (n.children) |*child| try self.applyNode(child, a, now);
    }
    /// Apply before re-layout, so width/height transitions move siblings too.
    pub fn apply(self: *Timeline, scene: *ui.Scene, now: f64) !void {
        if (!self.active()) return;
        try self.applyNode(scene.root, scene.arena.allocator(), now);
        scene.items.clearRetainingCapacity();
        scene.index.clearRetainingCapacity();
        try scene.layout(scene.root, scene.viewport, null);
        var i = self.tracks.items.len;
        while (i > 0) {
            i -= 1;
            const t = self.tracks.items[i];
            if (now >= t.start + t.config.delay + t.config.duration) self.remove(i);
        }
    }
};
