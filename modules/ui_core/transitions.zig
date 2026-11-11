//! Retained CSS transition state; the host schedules frames only while active.
const std = @import("std");
const ui = @import("root.zig");
const anim = @import("animation.zig");
const Tokens = @import("css_syntax.zig").Tokens;
pub const Value = union(enum) { number: f32, color: [4]u8, matrix: ui.transform.Matrix2D };
const Config = struct { duration: f32 = 0, delay: f32 = 0, curve: anim.Timing = .{ .bezier = anim.CubicBezier.ease } };
const Track = struct {
    id: u32,
    field: []const u8,
    from: Value,
    to: Value,
    start: f64,
    config: Config,
    fn sample(t: Track, now: f64) Value {
        const elapsed = @as(f32, @floatCast(now - t.start)) - t.config.delay;
        const p = if (elapsed < 0) @as(f32, 0) else if (elapsed >= t.config.duration or t.config.duration <= 0) @as(f32, 1) else t.config.curve.solve(elapsed / t.config.duration);
        return switch (t.from) {
            .number => |v| .{ .number = anim.interpolateNumber(v, t.to.number, p) },
            .color => |v| .{ .color = anim.interpolateColor(v, t.to.color, p) },
            .matrix => |v| .{ .matrix = anim.interpolateMatrix(v, t.to.matrix, p) },
        };
    }
};
fn matches(css: []const u8, field: []const u8) bool {
    if (std.mem.eql(u8, css, "all")) return true;
    var i: usize = 0;
    for (css) |c| {
        if (c == '-') continue;
        if (i >= field.len or std.ascii.toLower(c) != std.ascii.toLower(field[i])) return false;
        i += 1;
    }
    return i == field.len;
}
fn time(s: []const u8) ?f32 {
    if (std.mem.endsWith(u8, s, "ms")) return (std.fmt.parseFloat(f32, s[0 .. s.len - 2]) catch return null) / 1000;
    if (std.mem.endsWith(u8, s, "s")) return std.fmt.parseFloat(f32, s[0 .. s.len - 1]) catch null;
    return null;
}
fn config(style: ui.Style, field: []const u8) Config {
    var result = Config{};
    if (style.transition.len > 0) {
        var layers = Tokens{ .input = style.transition, .separators = "," };
        while (layers.next()) |layer| {
            var tokens = Tokens{ .input = layer, .separators = " \t" };
            var property: []const u8 = "all";
            var c = Config{};
            var times: usize = 0;
            while (tokens.next()) |token| {
                if (time(token)) |v| {
                    if (times == 0) c.duration = @max(0, v) else c.delay = v;
                    times += 1;
                } else if (std.mem.startsWith(u8, token, "ease") or std.mem.eql(u8, token, "linear") or std.mem.startsWith(u8, token, "cubic-bezier(") or std.mem.startsWith(u8, token, "steps(") or std.mem.startsWith(u8, token, "step-")) c.curve = anim.Timing.parse(token) else property = token;
            }
            if (matches(property, field)) result = c;
        }
    } else {
        var properties = Tokens{ .input = style.transitionProperty, .separators = "," };
        while (properties.next()) |property| if (matches(property, field)) {
            result = .{ .duration = @max(0, style.transitionDuration), .delay = style.transitionDelay, .curve = anim.Timing.parse(style.transitionTimingFunction) };
        };
    }
    return result;
}
fn equal(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .number => |v| v == b.number,
        .color => |v| std.mem.eql(u8, &v, &b.color),
        .matrix => |v| std.meta.eql(v, b.matrix),
    };
}
pub const Timeline = struct {
    allocator: std.mem.Allocator,
    tracks: std.ArrayList(Track) = .empty,
    pub fn init(a: std.mem.Allocator) Timeline {
        return .{ .allocator = a };
    }
    pub fn deinit(self: *Timeline) void {
        self.tracks.deinit(self.allocator);
    }
    pub fn active(self: *const Timeline) bool {
        return self.tracks.items.len > 0;
    }
    fn update(self: *Timeline, id: u32, field: []const u8, from: Value, to: Value, style: ui.Style, now: f64) !void {
        const c = config(style, field);
        for (self.tracks.items, 0..) |*t, i| if (t.id == id and std.mem.eql(u8, t.field, field)) {
            if (equal(t.to, to) and c.duration > 0) return;
            const current = t.sample(now);
            if (c.duration <= 0 or equal(current, to)) {
                _ = self.tracks.swapRemove(i);
                return;
            }
            t.* = .{ .id = id, .field = field, .from = current, .to = to, .start = now, .config = c };
            return;
        };
        if (c.duration <= 0 or equal(from, to)) return;
        try self.tracks.append(self.allocator, .{ .id = id, .field = field, .from = from, .to = to, .start = now, .config = c });
    }
    pub fn retarget(self: *Timeline, old: *const ui.Scene, target: *const ui.Scene, now: f64) !void {
        var i = self.tracks.items.len;
        while (i > 0) {
            i -= 1;
            if (target.find(self.tracks.items[i].id) == null) _ = self.tracks.swapRemove(i);
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
                            if (t.id == item.node.id and std.mem.eql(u8, t.field, name)) _ = self.tracks.swapRemove(k);
                        }
                    }
                } else if (T == []const u8 and comptime std.mem.endsWith(u8, name, "Color")) {
                    if (ui.gradient.parseColor(@field(before, name))) |v| if (ui.gradient.parseColor(@field(after, name))) |next| try self.update(item.node.id, name, .{ .color = v }, .{ .color = next }, after, now);
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
            if (now >= t.start + t.config.delay + t.config.duration) _ = self.tracks.swapRemove(i);
        }
    }
};
