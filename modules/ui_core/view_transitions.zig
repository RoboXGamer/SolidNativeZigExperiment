//! View Transitions Level 1 and Level 2 implementation.
//! Provides element capture, pseudo-element hierarchy generation (::view-transition,
//! ::view-transition-group, ::view-transition-image-pair, ::view-transition-old, ::view-transition-new),
//! transition class matching, and geometry/opacity cross-fade interpolation.
const std = @import("std");
const core = @import("root.zig");
const Rect = core.Rect;

pub const ElementSnapshot = struct {
    id: u32,
    name: []const u8,
    classes: []const []const u8 = &.{},
    rect: Rect,
    opacity: f32 = 1.0,
    transform: []const u8 = "",

    pub fn hasClass(self: ElementSnapshot, target_class: []const u8) bool {
        for (self.classes) |c| {
            if (std.mem.eql(u8, c, target_class)) return true;
        }
        return false;
    }
};

/// Matches a view-transition pseudo-element selector (e.g. "*", "header", "*.card", ".card")
/// against a named view transition and its view-transition-class set.
pub fn matchesPseudoSelector(name: []const u8, classes: []const []const u8, raw_selector: []const u8) bool {
    const s = std.mem.trim(u8, raw_selector, " \t\r\n");
    if (s.len == 0 or std.mem.eql(u8, s, "*")) return true;

    // Class selector: ".class" or "*.class"
    if (std.mem.startsWith(u8, s, "*.")) {
        const target_class = s[2..];
        for (classes) |c| if (std.mem.eql(u8, c, target_class)) return true;
        return false;
    }
    if (std.mem.startsWith(u8, s, ".")) {
        const target_class = s[1..];
        for (classes) |c| if (std.mem.eql(u8, c, target_class)) return true;
        return false;
    }

    // "name.class" compound selector
    if (std.mem.indexOfScalar(u8, s, '.')) |dot| {
        const target_name = s[0..dot];
        const target_class = s[dot + 1 ..];
        if (!std.mem.eql(u8, name, target_name)) return false;
        for (classes) |c| if (std.mem.eql(u8, c, target_class)) return true;
        return false;
    }

    return std.mem.eql(u8, name, s);
}

/// Represents the ::view-transition-old image pseudo-element.
pub const ViewTransitionOld = struct {
    snapshot: ElementSnapshot,
    opacity: f32 = 1.0,

    pub fn sample(self: ViewTransitionOld, progress: f32) f32 {
        const p = std.math.clamp(progress, 0, 1);
        return self.opacity * (1.0 - p);
    }
};

/// Represents the ::view-transition-new image pseudo-element.
pub const ViewTransitionNew = struct {
    snapshot: ElementSnapshot,
    opacity: f32 = 1.0,

    pub fn sample(self: ViewTransitionNew, progress: f32) f32 {
        const p = std.math.clamp(progress, 0, 1);
        return self.opacity * p;
    }
};

/// Represents the ::view-transition-image-pair pseudo-element.
pub const ViewTransitionImagePair = struct {
    name: []const u8,
    old_image: ?ViewTransitionOld = null,
    new_image: ?ViewTransitionNew = null,
};

/// Represents the ::view-transition-group pseudo-element.
/// Interpolates geometry from old snapshot to new snapshot.
pub const ViewTransitionGroup = struct {
    name: []const u8,
    classes: []const []const u8 = &.{},
    from_rect: Rect,
    to_rect: Rect,
    image_pair: ViewTransitionImagePair,

    pub fn sampleRect(self: ViewTransitionGroup, progress: f32) Rect {
        const p = std.math.clamp(progress, 0, 1);
        return .{
            .x = self.from_rect.x + (self.to_rect.x - self.from_rect.x) * p,
            .y = self.from_rect.y + (self.to_rect.y - self.from_rect.y) * p,
            .width = self.from_rect.width + (self.to_rect.width - self.from_rect.width) * p,
            .height = self.from_rect.height + (self.to_rect.height - self.from_rect.height) * p,
        };
    }
};

/// Represents the root ::view-transition pseudo-element.
pub const ViewTransition = struct {
    groups: std.ArrayList(ViewTransitionGroup),
    duration: f32 = 0.25, // default duration in seconds
    start_time: f64 = 0,

    pub fn init(allocator: std.mem.Allocator) ViewTransition {
        return .{ .groups = std.ArrayList(ViewTransitionGroup).init(allocator) };
    }

    pub fn deinit(self: *ViewTransition) void {
        self.groups.deinit();
    }

    /// Add a transition pair for matching old and new elements.
    pub fn addGroup(self: *ViewTransition, old_snap: ?ElementSnapshot, new_snap: ?ElementSnapshot) !void {
        if (old_snap == null and new_snap == null) return;
        const name = if (new_snap) |ns| ns.name else old_snap.?.name;
        const classes = if (new_snap) |ns| ns.classes else old_snap.?.classes;
        const from_rect = if (old_snap) |os| os.rect else new_snap.?.rect;
        const to_rect = if (new_snap) |ns| ns.rect else old_snap.?.rect;

        const group = ViewTransitionGroup{
            .name = name,
            .classes = classes,
            .from_rect = from_rect,
            .to_rect = to_rect,
            .image_pair = .{
                .name = name,
                .old_image = if (old_snap) |os| .{ .snapshot = os, .opacity = os.opacity } else null,
                .new_image = if (new_snap) |ns| .{ .snapshot = ns, .opacity = ns.opacity } else null,
            },
        };
        try self.groups.append(group);
    }
};

/// Resolves an element's effective view-transition-name.
/// If "match-element", returns an automatic element-scoped unique name.
pub fn resolveTransitionName(name: []const u8, element_id: u32, buf: *[32]u8) []const u8 {
    if (std.mem.eql(u8, name, "match-element") or std.mem.eql(u8, name, "auto")) {
        return std.fmt.bufPrint(buf, "vt-elem-{}", .{element_id}) catch "vt-elem";
    }
    return name;
}
