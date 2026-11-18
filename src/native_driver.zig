const std = @import("std");
const protocol = @import("host_driver");
const ui = @import("ui_core");
const rl = @import("raylib");
const bridge = @import("solid_bridge");
const accounting = @import("host_accounting");
const Input = @import("input.zig").Input;
extern fn ui_driver_start() c_int;
extern fn ui_driver_poll(*[*]const u8, *usize, *u64) c_int;
extern fn ui_driver_reply([*]const u8, usize) void;
extern fn ui_driver_stop() void;
extern fn ui_driver_flush() void;
extern fn getenv([*:0]const u8) ?[*:0]const u8;
extern fn ui_real_ns() u64;
extern fn ui_cpu_ns() u64;
extern "user32" fn InvalidateRect(?*anyopaque, ?*const anyopaque, c_int) c_int;
extern "user32" fn UpdateWindow(?*anyopaque) c_int;
extern "user32" fn SendMessageW(?*anyopaque, u32, usize, isize) isize;

pub const Driver = struct {
    session: protocol.Session = .{},
    allocator: std.mem.Allocator = std.heap.page_allocator,
    native_stats: accounting.Stats = .{},
    host_turns: u64 = 0,
    sample_motion: bool = true,
    active: bool = false,
    request: ?std.json.Parsed(protocol.Request) = null,
    synthetic: bool = false,
    input: Input = .{},
    target_time: ?u64 = null,
    phase: u8 = 0,
    turns: usize = 0,
    started: u64 = 0,
    failure: ?[]const u8 = null,
    preferences: ?ui.sizing.Context = null,
    preferences_changed: bool = false,
    close: bool = false,
    graph: u64 = 1,
    readback: u64 = 0,
    capture_result: ?struct { path: []const u8, width: i32, height: i32, readback: u64 } = null,
    buffer: [protocol.frame_limit]u8 = undefined,
    pub fn start(self: *Driver, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.active = ui_driver_start() != 0;
    }
    pub fn stop(self: *Driver) void {
        if (self.active) ui_driver_stop();
        if (self.request) |p| p.deinit();
    }
    pub fn begin(self: *Driver, runtime: *bridge.Runtime, scene: *ui.Scene, revision: u64, scene_revision: usize) void {
        self.host_turns += 1;
        self.sample_motion = true;
        self.input.next();
        if (self.request != null) return;
        var bytes: [*]const u8 = undefined;
        var len: usize = 0;
        var connection: u64 = 0;
        if (!self.active or ui_driver_poll(&bytes, &len, &connection) == 0) return;
        if (len == std.math.maxInt(usize)) {
            self.synthetic = false;
            self.input = .{};
            self.session.authenticated = false;
            ui_driver_reply("{}", 2);
            return;
        }
        if (connection != self.session.connection) {
            self.session.authenticated = false;
            self.session.high_id = 0;
            self.session.ids = @splat(0);
            self.session.connection = connection;
        }
        self.request = protocol.decode(self.allocator, bytes[0..len]) catch |err| {
            self.rawError(@errorName(err));
            return;
        };
        self.started = ui_real_ns();
        self.turns = 0;
        self.phase = 0;
        self.failure = null;
        self.target_time = null;
        self.capture_result = null;
        const r = self.request.?.value;
        self.accept(runtime, scene, revision, scene_revision, r) catch |err| {
            self.failure = @errorName(err);
        };
    }
    fn accept(self: *Driver, runtime: *bridge.Runtime, scene: *ui.Scene, revision: u64, scene_revision: usize, r: protocol.Request) !void {
        try r.validate();
        if (r.is("hello")) {
            if (self.session.authenticated) return error.AlreadyAuthenticated;
            const token = std.mem.span(getenv("SOLID_NATIVE_TOKEN") orelse return error.AuthenticationFailed);
            if (!std.mem.eql(u8, r.token orelse "", token)) return error.AuthenticationFailed;
            self.session.authenticated = true;
        } else {
            if (!self.session.authenticated or r.session != self.session.connection) return error.InvalidSession;
            if (r.generation != runtime.runtimeGeneration()) return error.StaleRuntime;
        }
        if (try self.session.cached(r.id)) |cached| {
            ui_driver_reply(cached.ptr, cached.len);
            self.request.?.deinit();
            self.request = null;
            return;
        }
        // Reserve before mutation. A reply allocation/export failure must never
        // make an uncertain click eligible for execution a second time.
        self.session.high_id = r.id;
        if (r.cursor) |cursor| {
            if (cursor.revision != revision or cursor.scene != scene_revision or cursor.graph != self.graph) return error.StaleCursor;
        }
        if (r.is("clock.advance") or r.is("settle")) {
            self.target_time = try runtime.target(if (r.is("settle")) 0 else r.ms orelse return error.MissingTime);
            return;
        }
        if (r.is("resize")) {
            rl.setWindowSize(r.width orelse return error.MissingSize, r.height orelse return error.MissingSize);
            return;
        }
        if (r.is("prefer") or r.is("reset")) {
            if (r.is("reset")) {
                self.preferences = null;
            } else {
                var ctx = self.preferences orelse scene.length_context;
                const p = r.preference orelse return error.MissingPreference;
                const value = r.value orelse return error.MissingPreference;
                if (std.mem.eql(u8, p, "color-scheme")) ctx.color_scheme = std.meta.stringToEnum(@TypeOf(ctx.color_scheme), value) orelse return error.UnsupportedPreference else if (std.mem.eql(u8, p, "reduced-motion")) ctx.reduced_motion = std.meta.stringToEnum(@TypeOf(ctx.reduced_motion), value) orelse return error.UnsupportedPreference else if (std.mem.eql(u8, p, "contrast")) ctx.contrast = std.meta.stringToEnum(@TypeOf(ctx.contrast), value) orelse return error.UnsupportedPreference else return error.UnsupportedPreference;
                self.preferences = ctx;
            }
            self.preferences_changed = true;
            return;
        }
        if (r.is("close")) {
            self.close = true;
            return;
        }
        if (r.is("surface.expose")) {
            _ = InvalidateRect(rl.getWindowHandle(), null, 0);
            _ = UpdateWindow(rl.getWindowHandle());
            _ = SendMessageW(rl.getWindowHandle(), 0x000f, 0, 0);
            return;
        }
        if (r.is("screenshot")) {
            const p = r.path orelse return error.MissingPath;
            if (p.len > 4096 or std.mem.indexOfScalar(u8, p, 0) != null or !std.mem.endsWith(u8, p, ".png")) return error.InvalidPath;
            return;
        }
        if (r.is("hello") or r.is("tree") or r.is("layout") or r.is("logs") or r.is("metrics")) return;
        if (r.is("pointer.cancel")) {
            self.synthetic = true;
            self.input.down = false;
            return;
        }
        if (r.is("pointer.move") or r.is("pointer.down") or r.is("pointer.up") or r.is("click")) {
            if (r.target) |target| {
                const id = try resolve(scene, target);
                const item = scene.find(id) orelse return error.StaleTarget;
                const matrix = scene.worldTransform(item);
                const pos = matrix.transformPoint(.{ .x = item.bounds.x + item.bounds.width / 2, .y = item.bounds.y + item.bounds.height / 2 });
                if (scene.hitTest(pos.x, pos.y) != id) return error.ObscuredTarget;
                self.synthetic = true;
                self.input.pointer = .{ .x = pos.x, .y = pos.y };
            } else {
                self.synthetic = true;
                self.input.pointer = .{ .x = r.x orelse return error.MissingPoint, .y = r.y orelse return error.MissingPoint };
            }
            self.input.inside = true;
            if (r.is("click") or r.is("pointer.down")) {
                self.input.press = true;
                self.input.down = true;
            }
            if (r.is("pointer.up")) {
                self.input.release = true;
                self.input.down = false;
            }
            return;
        }
        if (r.is("key.down") or r.is("key.up")) {
            const key = try Input.parseKey(r.key orelse return error.MissingKey);
            self.synthetic = true;
            const index: @TypeOf(@as(usize, 0)) = @intCast(@backingInt(key));
            self.input.keys[index] = r.is("key.down");
            self.input.presses[index] = r.is("key.down");
            return;
        }
        if (r.is("type")) {
            const text = r.text orelse return error.MissingText;
            if (text.len > self.input.text.len) return error.TextTooLarge;
            self.synthetic = true;
            @memcpy(self.input.text[0..text.len], text);
            self.input.text_len = text.len;
            return;
        }
        if (r.is("scroll")) {
            self.synthetic = true;
            self.input.pointer = .{ .x = r.x orelse return error.MissingPoint, .y = r.y orelse return error.MissingPoint };
            self.input.wheel_x = r.dx orelse 0;
            self.input.wheel_y = r.dy orelse 0;
            return;
        }
    }
    pub fn step(self: *Driver, runtime: *bridge.Runtime, motion: bool) void {
        if (self.request == null or self.failure != null) return;
        self.turns += 1;
        if (self.turns > 10000 or ui_real_ns() - self.started > 10_000_000_000) {
            self.failure = "AdvanceBudgetExceeded";
            self.target_time = null;
            return;
        }
        if (self.target_time) |t| {
            if (self.turns > 10000 or ui_real_ns() - self.started > 10_000_000_000) {
                self.failure = "AdvanceBudgetExceeded";
                self.target_time = null;
                return;
            }
            const done = runtime.step(t, motion) catch |err| {
                self.failure = @errorName(err);
                self.target_time = null;
                return;
            };
            self.sample_motion = done or runtime.atFrame() or runtime.now() == bridge.app_clock.milliseconds(t);
            if (done) self.target_time = null;
        }
    }
    pub fn again(self: *Driver, runtime: *bridge.Runtime, reconcile: bool) bool {
        if (self.request != null and self.failure == null and reconcile) return true;
        if (self.target_time != null) return true;
        if (self.request) |p| if (p.value.is("click") and self.phase == 0 and self.failure == null) {
            self.phase = 1;
            return true;
        };
        if (self.request != null and self.failure == null and runtime.controlled() and runtime.due()) {
            self.target_time = runtime.target(0) catch unreachable;
            return true;
        }
        return false;
    }
    pub fn wantsCapture(self: *Driver) bool {
        return if (self.request) |p| p.value.is("screenshot") and self.failure == null else false;
    }
    pub fn capture(self: *Driver, allocator: std.mem.Allocator) !void {
        if (!self.wantsCapture()) return;
        if (rl.isWindowMinimized() or rl.getRenderWidth() <= 0 or rl.getRenderHeight() <= 0) {
            self.failure = "SurfaceUnavailable";
            return;
        }
        const path = self.request.?.value.path.?;
        const z = try allocator.dupeSentinel(u8, path, 0);
        rl.gl.rlDrawRenderBatchActive();
        const image = try rl.loadImageFromScreen();
        defer image.unload();
        if (!image.exportToFile(z)) return error.CaptureFailed;
        self.readback += 1;
        self.capture_result = .{ .path = path, .width = image.width, .height = image.height, .readback = self.readback };
    }
    pub fn releaseClick(self: *Driver) void {
        if (self.phase == 1) {
            self.input.release = true;
            self.input.down = false;
            self.phase = 2;
        }
    }
    fn rawError(self: *Driver, message: []const u8) void {
        var w: std.Io.Writer = .fixed(&self.buffer);
        std.json.Stringify.value(.{ .version = 1, .id = @as(u64, 0), .@"error" = message }, .{}, &w) catch return;
        ui_driver_reply(w.buffered().ptr, w.buffered().len);
    }
    pub fn transportError(self: *Driver, message: []const u8) void {
        self.rawError(message);
    }
    pub fn flush(self: *Driver) void {
        _ = self;
        ui_driver_flush();
    }
    pub fn reply(self: *Driver, runtime: *bridge.Runtime, tree: *ui.Tree, scene: *ui.Scene, scene_revision: usize, layouts: usize, paints: usize, submitted: u64, allocator: std.mem.Allocator) !void {
        const parsed = self.request orelse return;
        const r = parsed.value;
        defer {
            parsed.deinit();
            self.request = null;
        }
        const Node = struct { node: u32, parent: ?u32, type: []const u8, testId: []const u8, role: []const u8, name: []const u8, text: []const u8, value: []const u8, disabled: bool, bounds: ui.Rect, opacity: f32 };
        var nodes: std.ArrayList(Node) = .empty;
        const offset = if (r.cursor) |c| c.offset else 0;
        var next: ?protocol.Cursor = null;
        if ((r.is("tree") or r.is("layout")) and self.failure == null) {
            if (offset > scene.items.items.len) self.failure = "InvalidCursor" else {
                const end = @min(scene.items.items.len, offset + (r.limit orelse 64));
                for (scene.items.items[offset..end]) |item| {
                    const n = item.node;
                    var name_buffer: [1024]u8 = undefined;
                    const name = if (n.name.len > 0) n.name else if (n.role.len > 0) try allocator.dupe(u8, semanticName(n, &name_buffer)) else "";
                    try nodes.append(allocator, .{ .node = n.id, .parent = item.parent_id, .type = n.type, .testId = n.testId, .role = n.role, .name = name, .text = n.text, .value = n.value, .disabled = n.disabled, .bounds = item.bounds, .opacity = n.style.opacity });
                }
                if (end < scene.items.items.len) next = .{ .revision = tree.revisions.state, .scene = scene_revision, .graph = self.graph, .offset = end };
            }
        }
        const captured = self.capture_result;
        var writer: std.Io.Writer = .fixed(&self.buffer);
        std.json.Stringify.value(.{
            .version = 1,
            .id = r.id,
            .session = self.session.connection,
            .generation = runtime.runtimeGeneration(),
            .graph = self.graph,
            .appTime = runtime.now(),
            .clock = .{ .mode = if (runtime.controlled()) "controlled" else "live", .epoch = bridge.app_clock.epoch_ms, .horizonMs = bridge.app_clock.milliseconds(bridge.app_clock.horizon) },
            .revisions = .{ .tree = tree.revisions.state, .scene = scene_revision, .layout = layouts, .paint = paints, .submitted = submitted },
            .evidence = if (captured != null) "gpu-readback" else "native-ready",
            .physicalPresentation = false,
            .pending = .{ .timers = runtime.pending(), .jobs = runtime.jobsPending(), .nextTimeout = runtime.nextTimeout(), .nextDeadlineMs = runtime.nextDeadline(), .externalWork = "unobserved" },
            .real = .{ .monotonicNs = ui_real_ns(), .cpuNs = ui_cpu_ns(), .hostTurns = self.host_turns },
            .@"error" = self.failure,
            .nodes = nodes.items,
            .cursor = next,
            .capture = captured,
            .metrics = runtime.schedulerMetrics(),
            .quickjs = runtime.memory(),
            .native = self.native_stats,
            .driverStorageBytes = @sizeOf(Driver),
            .input = .{ .pointerDown = self.input.down, .keysHeld = std.mem.count(bool, &self.input.keys, &.{true}) },
            .logs = if (r.is("logs")) try runtime.logs(allocator) else null,
            .viewport = .{ .width = rl.getScreenWidth(), .height = rl.getScreenHeight(), .framebufferWidth = rl.getRenderWidth(), .framebufferHeight = rl.getRenderHeight(), .scale = rl.getWindowScaleDPI() },
            .capabilities = if (r.is("hello")) &protocol.commands else &.{},
            .preferences = if (r.is("hello")) &[_][]const u8{ "color-scheme", "contrast", "reduced-motion" } else &.{},
            .keys = if (r.is("hello")) &Input.key_names else &.{},
            .limits = .{ .frame = protocol.frame_limit, .inFlight = 1, .page = protocol.page_limit, .cached = protocol.cache_limit, .turns = 10000 },
        }, .{}, &writer) catch {
            self.rawError("ResponseTooLarge");
            self.session.high_id = @max(self.session.high_id, r.id);
            return;
        };
        const bytes = writer.buffered();
        if (self.session.authenticated) self.session.remember(r.id, bytes);
        ui_driver_reply(bytes.ptr, bytes.len);
        if (r.is("close") and self.failure == null) ui_driver_flush();
    }
};
fn resolve(scene: *ui.Scene, target: protocol.Target) !u32 {
    var found: ?u32 = null;
    for (scene.items.items) |item| {
        const n = item.node;
        if (target.node) |id| {
            if (n.id != id) continue;
        }
        if (target.testId) |id| {
            if (!std.mem.eql(u8, n.testId, id)) continue;
        }
        if (target.role) |role| {
            if (!std.mem.eql(u8, n.role, role)) continue;
        }
        if (target.name) |name| {
            var buffer: [1024]u8 = undefined;
            if (!std.mem.eql(u8, if (n.name.len > 0) n.name else semanticName(n, &buffer), name)) continue;
        }
        if (found) |previous| if (previous != n.id) return error.AmbiguousTarget;
        if (n.disabled) return error.DisabledTarget;
        found = n.id;
    }
    return found orelse error.TargetNotFound;
}
fn semanticName(node: *const ui.Node, buffer: []u8) []const u8 {
    return std.mem.trim(u8, buffer[0..appendName(node, buffer)], " \r\n\t");
}
fn appendName(node: *const ui.Node, buffer: []u8) usize {
    var length = @min(buffer.len, node.text.len);
    @memcpy(buffer[0..length], node.text[0..length]);
    for (node.children) |*child| {
        if (length == buffer.len) break;
        length += appendName(child, buffer[length..]);
    }
    return length;
}
