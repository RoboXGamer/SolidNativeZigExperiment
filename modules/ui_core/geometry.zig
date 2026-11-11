//! Geometry primitives modelled after the Web `DOMRect` API.
//!
//! `DOMRect` stores `x`/`y`/`width`/`height` and exposes the derived edges
//! `left`/`top`/`right`/`bottom`. Layout code should use those derived edges
//! (and `Edges` rings) instead of recomputing `x + width` in every module, so a
//! box never needs a bespoke formula per call site.
const std = @import("std");

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,

    pub const zero: Rect = .{};

    pub fn left(self: Rect) f32 {
        return self.x;
    }
    pub fn top(self: Rect) f32 {
        return self.y;
    }
    pub fn right(self: Rect) f32 {
        return self.x + self.width;
    }
    pub fn bottom(self: Rect) f32 {
        return self.y + self.height;
    }
    pub fn isEmpty(self: Rect) bool {
        return self.width <= 0 or self.height <= 0;
    }
    /// Point-in-rect test using half-open edges, matching DOM hit testing.
    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.left() and px < self.right() and py >= self.top() and py < self.bottom();
    }
    pub fn translate(self: Rect, dx: f32, dy: f32) Rect {
        return .{ .x = self.x + dx, .y = self.y + dy, .width = self.width, .height = self.height };
    }
    /// Shrink by an inner ring (padding or border): the content/padding box.
    pub fn inset(self: Rect, ring: Edges) Rect {
        return .{
            .x = self.x + ring.left,
            .y = self.y + ring.top,
            .width = @max(0, self.width - ring.horizontal()),
            .height = @max(0, self.height - ring.vertical()),
        };
    }
    /// Grow by an outer ring (border or margin).
    pub fn outset(self: Rect, ring: Edges) Rect {
        return .{
            .x = self.x - ring.left,
            .y = self.y - ring.top,
            .width = self.width + ring.horizontal(),
            .height = self.height + ring.vertical(),
        };
    }
    /// Overlap of two rects; an empty rect when they do not intersect.
    pub fn intersect(self: Rect, other: Rect) Rect {
        const x0 = @max(self.left(), other.left());
        const y0 = @max(self.top(), other.top());
        const x1 = @min(self.right(), other.right());
        const y1 = @min(self.bottom(), other.bottom());
        return .{ .x = x0, .y = y0, .width = @max(0, x1 - x0), .height = @max(0, y1 - y0) };
    }
};

/// A one-sided ring around a box: padding, border or margin.
pub const Edges = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,

    pub const zero: Edges = .{};

    pub fn uniform(value: f32) Edges {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }
    pub fn horizontal(self: Edges) f32 {
        return self.left + self.right;
    }
    pub fn vertical(self: Edges) f32 {
        return self.top + self.bottom;
    }
    pub fn add(self: Edges, other: Edges) Edges {
        return .{
            .top = self.top + other.top,
            .right = self.right + other.right,
            .bottom = self.bottom + other.bottom,
            .left = self.left + other.left,
        };
    }
};

test "DOMRect edges and containment" {
    const r = Rect{ .x = 10, .y = 20, .width = 100, .height = 50 };
    try std.testing.expectEqual(@as(f32, 10), r.left());
    try std.testing.expectEqual(@as(f32, 20), r.top());
    try std.testing.expectEqual(@as(f32, 110), r.right());
    try std.testing.expectEqual(@as(f32, 70), r.bottom());
    try std.testing.expect(r.contains(10, 20));
    try std.testing.expect(r.contains(109, 69));
    try std.testing.expect(!r.contains(110, 20));
    try std.testing.expect(!r.contains(10, 70));
}

test "inset and outset are inverse" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const ring = Edges{ .top = 2, .right = 3, .bottom = 5, .left = 7 };
    const inner = r.inset(ring);
    try std.testing.expectEqual(@as(f32, 7), inner.x);
    try std.testing.expectEqual(@as(f32, 2), inner.y);
    try std.testing.expectEqual(@as(f32, 90), inner.width);
    try std.testing.expectEqual(@as(f32, 33), inner.height);
    const outer = inner.outset(ring);
    try std.testing.expectEqual(r.x, outer.x);
    try std.testing.expectEqual(r.width, outer.width);
    try std.testing.expectEqual(r.height, outer.height);
}

test "intersect clamps to the overlap" {
    const a = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    const b = Rect{ .x = 25, .y = 10, .width = 50, .height = 20 };
    const i = a.intersect(b);
    try std.testing.expectEqual(@as(f32, 25), i.x);
    try std.testing.expectEqual(@as(f32, 10), i.y);
    try std.testing.expectEqual(@as(f32, 25), i.width);
    try std.testing.expectEqual(@as(f32, 20), i.height);
    try std.testing.expect(a.intersect(Rect{ .x = 100, .y = 100, .width = 5, .height = 5 }).isEmpty());
}
