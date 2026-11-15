//! Typed phase inputs shared by the retained tree and the native delta protocol.
const std = @import("std");
const styles = @import("style.zig");
pub const LayoutInputs = struct {
    type: []const u8 = "root",
    text: []const u8 = "",
    value: []const u8 = "",
    placeholder: []const u8 = "",
    intrinsicAspectRatio: ?f32 = null,
    children: []const u32 = &.{},
    style: styles.LayoutStyle = .{},
};
pub const PaintInputs = struct {
    readOnly: bool = false,
    readWrite: bool = false,
    visibilitySpecified: bool = false,
    style: styles.PaintStyle = .{},
};
pub const InteractionInputs = struct {
    clickable: bool = false,
    focusable: bool = false,
    tabIndex: ?i32 = null,
    hovered: bool = false,
    active: bool = false,
    focused: bool = false,
    popoverOpen: bool = false,
    style: styles.InteractionStyle = .{},
};
pub const Delta = struct {
    id: u32,
    layout: ?LayoutInputs = null,
    paint: ?PaintInputs = null,
    interaction: ?InteractionInputs = null,
    motion: ?styles.MotionStyle = null,
    pub fn effects(self: Delta, previous: anytype) Changes {
        var changes: Changes = .{};
        if (self.layout) |values| if (!equal(values, select(LayoutInputs, previous))) {
            changes.geometry();
        };
        if (self.paint) |values| if (!equal(values, select(PaintInputs, previous))) {
            changes.state = true;
            changes.paint = true;
            changes.cursor = true;
        };
        if (self.interaction) |values| if (!equal(values, select(InteractionInputs, previous))) {
            changes.state = true;
            changes.cursor = true;
        };
        if (self.motion) |values| if (!equal(values, styles.select(styles.MotionStyle, previous.style))) {
            changes.state = true;
        };
        return changes;
    }
    pub fn apply(self: Delta, node: anytype) void {
        if (self.layout) |values| assignNode(node, values);
        if (self.paint) |values| assignNode(node, values);
        if (self.interaction) |values| assignNode(node, values);
        if (self.motion) |values| styles.assign(&node.style, values);
    }
};
fn assignNode(node: anytype, values: anytype) void {
    inline for (@typeInfo(@TypeOf(values)).@"struct".field_names) |name| {
        if (comptime std.mem.eql(u8, name, "style")) styles.assign(&node.style, values.style) else if (comptime std.mem.eql(u8, name, "visibilitySpecified")) {
            node.style.interactionSpecified = (node.style.interactionSpecified & ~@as(u32, 1)) | @as(u32, @intFromBool(values.visibilitySpecified));
        } else @field(node, name) = @field(values, name);
    }
}
pub fn setInteraction(node: anytype, values: InteractionInputs) void {
    assignNode(node, values);
}
pub fn select(comptime Inputs: type, node: anytype) Inputs {
    var result: Inputs = undefined;
    inline for (@typeInfo(Inputs).@"struct".field_names, @typeInfo(Inputs).@"struct".field_types) |name, T| {
        if (comptime std.mem.eql(u8, name, "style")) @field(result, name) = styles.select(T, node.style) else if (comptime std.mem.eql(u8, name, "visibilitySpecified")) result.visibilitySpecified = node.style.interactionSpecified & 1 != 0 else @field(result, name) = @field(node, name);
    }
    return result;
}
pub const Changes = struct {
    state: bool = false,
    cursor: bool = false,
    paint: bool = false,
    layout: bool = false,
    pub fn geometry(self: *Changes) void {
        self.* = .{ .state = true, .cursor = true, .paint = true, .layout = true };
    }
    pub fn merge(self: *Changes, other: Changes) void {
        self.state = self.state or other.state;
        self.cursor = self.cursor or other.cursor;
        self.paint = self.paint or other.paint;
        self.layout = self.layout or other.layout;
    }
};
pub const Revisions = struct {
    layout: u64 = 0,
    paint: u64 = 0,
    interaction: u64 = 0,
    state: u64 = 0,
    pub fn advance(self: *Revisions, changes: Changes) void {
        if (changes.layout) self.layout += 1;
        if (changes.paint) self.paint += 1;
        if (changes.cursor) self.interaction += 1;
        if (changes.state) self.state += 1;
    }
};
pub fn equal(a: anytype, b: @TypeOf(a)) bool {
    @setEvalBranchQuota(200000);
    return switch (@typeInfo(@TypeOf(a))) {
        .pointer => |p| if (p.size == .slice) std.mem.eql(p.child, a, b) else a == b,
        .optional => if (a) |v| if (b) |w| equal(v, w) else false else b == null,
        .@"struct" => blk: {
            inline for (@typeInfo(@TypeOf(a)).@"struct".field_names) |name| if (!equal(@field(a, name), @field(b, name))) break :blk false;
            break :blk true;
        },
        else => std.meta.eql(a, b),
    };
}
pub fn difference(before: anytype, after: @TypeOf(before)) Changes {
    var changes: Changes = .{};
    if (!equal(select(LayoutInputs, before), select(LayoutInputs, after))) changes.geometry();
    if (!equal(select(PaintInputs, before), select(PaintInputs, after))) {
        changes.state = true;
        changes.paint = true;
        changes.cursor = true;
    }
    if (!equal(select(InteractionInputs, before), select(InteractionInputs, after))) {
        changes.state = true;
        changes.cursor = true;
    }
    if (!equal(styles.select(styles.MotionStyle, before.style), styles.select(styles.MotionStyle, after.style))) changes.state = true;
    return changes;
}
