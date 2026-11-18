//! Transport-independent v1 validation/session state. UI thread owns execution.
const std = @import("std");
pub const frame_limit = 65536;
pub const page_limit = 256;
pub const cache_limit = 16;
pub const commands = [_][]const u8{ "hello", "tree", "layout", "logs", "pointer.move", "pointer.down", "pointer.up", "pointer.cancel", "click", "key.down", "key.up", "type", "scroll", "resize", "prefer", "reset", "clock.advance", "settle", "metrics", "screenshot", "surface.expose", "close" };
pub const Target = struct { node: ?u32 = null, testId: ?[]const u8 = null, role: ?[]const u8 = null, name: ?[]const u8 = null };
pub const Cursor = struct { revision: u64, scene: usize, graph: u64, offset: usize };
pub const Request = struct {
    version: u32,
    id: u64,
    cmd: []const u8,
    token: ?[]const u8 = null,
    session: ?u64 = null,
    generation: ?u64 = null,
    target: ?Target = null,
    x: ?f32 = null,
    y: ?f32 = null,
    dx: ?f32 = null,
    dy: ?f32 = null,
    key: ?[]const u8 = null,
    text: ?[]const u8 = null,
    ms: ?f64 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    preference: ?[]const u8 = null,
    value: ?[]const u8 = null,
    cursor: ?Cursor = null,
    limit: ?usize = null,
    path: ?[]const u8 = null,
    pub fn is(self: Request, name: []const u8) bool {
        return std.mem.eql(u8, self.cmd, name);
    }
    pub fn validate(self: Request) !void {
        if (self.version != 1) return error.UnsupportedVersion;
        if (self.id == 0 or self.id > 9_007_199_254_740_991) return error.InvalidId;
        var known = false;
        for (commands) |c| {
            if (self.is(c)) known = true;
        }
        if (!known) return error.UnknownCommand;
        inline for (.{ "x", "y", "dx", "dy" }) |f| if (@field(self, f)) |n| {
            if (!std.math.isFinite(n) or @abs(n) > 1e6) return error.InvalidGeometry;
        };
        if (self.ms) |n| {
            if (!std.math.isFinite(n) or n < 0 or n > 9_007_199_254.0) return error.InvalidTime;
        }
        if (self.width) |n| {
            if (n < 1 or n > 8192) return error.InvalidSize;
        }
        if (self.height) |n| {
            if (n < 1 or n > 8192) return error.InvalidSize;
        }
        if (self.limit) |n| {
            if (n < 1 or n > page_limit) return error.InvalidPage;
        }
        if (self.text) |s| if (!std.unicode.utf8ValidateSlice(s) or std.mem.indexOfScalar(u8, s, 0) != null) return error.InvalidText;
        // Reject recognized-but-inapplicable fields as well as unknown JSON keys.
        inline for (@typeInfo(Request).@"struct".field_names) |f| {
            if (comptime !std.mem.eql(u8, f, "version") and !std.mem.eql(u8, f, "id") and !std.mem.eql(u8, f, "cmd") and !std.mem.eql(u8, f, "session") and !std.mem.eql(u8, f, "generation")) {
                if (@field(self, f) != null and !allowed(self.cmd, f)) return error.UnexpectedField;
            }
        }
        if (self.target) |t| {
            const count = @as(u8, @intFromBool(t.node != null)) + @as(u8, @intFromBool(t.testId != null)) + @as(u8, @intFromBool(t.role != null or t.name != null));
            if (count != 1) return error.InvalidTarget;
        }
        if (self.is("click") or self.is("pointer.move") or self.is("pointer.down") or self.is("pointer.up")) {
            if (self.target == null and (self.x == null or self.y == null)) return error.MissingPoint;
            if (self.target != null and (self.x != null or self.y != null)) return error.UnexpectedField;
        }
        if (self.is("scroll") and (self.x == null or self.y == null)) return error.MissingPoint;
        if (self.is("resize") and (self.width == null or self.height == null)) return error.MissingSize;
        if (self.is("clock.advance") and self.ms == null) return error.MissingTime;
        if (std.mem.startsWith(u8, self.cmd, "key.") and self.key == null) return error.MissingKey;
        if (self.is("type") and (self.text == null or self.text.?.len > 4096)) return error.InvalidText;
        if (self.is("screenshot") and self.path == null) return error.MissingPath;
    }
};
fn allowed(cmd: []const u8, field: []const u8) bool {
    const set: []const u8 = if (std.mem.eql(u8, cmd, "hello")) " token " else if (std.mem.eql(u8, cmd, "tree") or std.mem.eql(u8, cmd, "layout")) " cursor limit " else if (std.mem.startsWith(u8, cmd, "pointer.") or std.mem.eql(u8, cmd, "click")) " target x y " else if (std.mem.startsWith(u8, cmd, "key.")) " key " else if (std.mem.eql(u8, cmd, "type")) " text " else if (std.mem.eql(u8, cmd, "scroll")) " x y dx dy " else if (std.mem.eql(u8, cmd, "resize")) " width height " else if (std.mem.eql(u8, cmd, "prefer")) " preference value " else if (std.mem.eql(u8, cmd, "clock.advance")) " ms " else if (std.mem.eql(u8, cmd, "screenshot")) " path " else " ";
    var it = std.mem.tokenizeScalar(u8, set, ' ');
    while (it.next()) |f| if (std.mem.eql(u8, f, field)) return true;
    return false;
}
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Request) {
    const parsed = try decode(allocator, bytes);
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Request) {
    if (bytes.len > frame_limit) return error.FrameTooLarge;
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
    const parsed = try std.json.parseFromSlice(Request, allocator, bytes, .{ .max_value_len = frame_limit, .allocate = .alloc_always });
    return parsed;
}
pub const Session = struct {
    authenticated: bool = false,
    connection: u64 = 0,
    high_id: u64 = 0,
    ids: [cache_limit]u64 = @splat(0),
    lengths: [cache_limit]usize = @splat(0),
    replies: [cache_limit][frame_limit]u8 = undefined,
    pub fn cached(self: *Session, id: u64) !?[]const u8 {
        for (self.ids, 0..) |n, i| if (n == id) return self.replies[i][0..self.lengths[i]];
        if (id <= self.high_id) return error.ResultUncertain;
        return null;
    }
    pub fn remember(self: *Session, id: u64, reply: []const u8) void {
        const slot = id % cache_limit;
        self.ids[slot] = id;
        self.lengths[slot] = reply.len;
        @memcpy(self.replies[slot][0..reply.len], reply);
        self.high_id = @max(self.high_id, id);
    }
};
test "strict protocol refuses unknown/inapplicable fields before mutation" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.UnknownField, parse(a, "{\"version\":1,\"id\":1,\"cmd\":\"settle\",\"eval\":\"x\"}"));
    try std.testing.expectError(error.UnexpectedField, parse(a, "{\"version\":1,\"id\":1,\"cmd\":\"settle\",\"ms\":1}"));
    try std.testing.expectError(error.InvalidTime, parse(a, "{\"version\":1,\"id\":1,\"cmd\":\"clock.advance\",\"ms\":-1}"));
    const p = try parse(a, "{\"version\":1,\"id\":1,\"cmd\":\"type\",\"text\":\"hi \\uD83D\\uDE00\\n\\\"\"}");
    defer p.deinit();
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, parse(failing.allocator(), "{\"version\":1,\"id\":1,\"cmd\":\"hello\"}"));
}
test "duplicate results and evicted uncertain mutations" {
    const s = try std.testing.allocator.create(Session);
    defer std.testing.allocator.destroy(s);
    s.* = .{};
    s.remember(1, "done");
    try std.testing.expectEqualStrings("done", (try s.cached(1)).?);
    s.remember(17, "next");
    try std.testing.expectError(error.ResultUncertain, s.cached(1));
}
fn allocationFixture(a: std.mem.Allocator) !void {
    const p = try parse(a, "{\"version\":1,\"id\":1,\"cmd\":\"type\",\"text\":\"owned \\uD83D\\uDE00 string\"}");
    defer p.deinit();
    try std.testing.expectEqualStrings("owned 😀 string", p.value.text.?);
}
test "all protocol allocation failures release owned request data" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFixture, .{});
}
