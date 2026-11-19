//! Explicit test build: identical complete UI turns with/without the pipe driver.
const std = @import("std");
const ui = @import("ui_core");
const bridge = @import("solid_bridge");
const rl = @import("raylib");
const Input = @import("input.zig").Input;
const Stats = @import("host_accounting").Stats;
extern fn ui_real_ns() u64;
extern fn ui_cpu_ns() u64;
const Phase = enum { cold, noop, paint, layout, inspection, idle, done };
const Record = struct { name: Phase, wallNs: u64, cpuNs: u64, appTime: f64, paints: usize, layouts: usize, native: Stats, quickjs: bridge.Memory, sceneHash: u64, inspectionBytes: usize };
pub const Profile = struct {
    phase: Phase = .cold,
    turns: usize = 0,
    done_advance: bool = false,
    wall: u64,
    cpu: u64,
    paints: usize = 0,
    layouts: usize = 0,
    records: [6]Record = undefined,
    count: usize = 0,
    inspection_bytes: usize = 0,
    pub fn init() Profile {
        return .{ .wall = ui_real_ns(), .cpu = ui_cpu_ns() };
    }
    pub fn before(self: *Profile, runtime: *bridge.Runtime) !Input {
        rl.disableEventWaiting();
        if (self.phase == .paint or self.phase == .layout) {
            self.done_advance = try runtime.step(try bridge.app_clock.fromMs(if (self.phase == .paint) 50 else 100), false);
        }
        if (self.phase == .idle) rl.enableEventWaiting();
        return .{ .pointer = .{ .x = -10 - @as(f32, @floatFromInt(self.turns % 120)), .y = -10 }, .inside = true };
    }
    pub fn wait(self: *Profile) ?f64 {
        if (self.phase != .idle) return null;
        return @as(f64, @floatFromInt(200_000_000 -| (ui_real_ns() - self.wall))) / 1e9;
    }
    pub fn after(self: *Profile, runtime: *bridge.Runtime, scene: *ui.Scene, paints: usize, layouts: usize, stats: Stats, a: std.mem.Allocator, driver: bool, storage: usize) !bool {
        self.turns += 1;
        if (self.turns > 2000) return error.ProfileTurnLimit;
        if (self.phase == .inspection) {
            const Projection = struct { node: u32, parent: ?u32, bounds: ui.Rect, opacity: f32 };
            const start = (self.turns % 2) * 64;
            const end = @min(scene.items.items.len, start + 64);
            const nodes = try a.alloc(Projection, end - start);
            for (scene.items.items[start..end], nodes) |item, *n| n.* = .{ .node = item.node.id, .parent = item.parent_id, .bounds = item.bounds, .opacity = item.node.style.opacity };
            var bytes: [65536]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&bytes);
            try std.json.Stringify.value(nodes, .{}, &writer);
            self.inspection_bytes += writer.buffered().len;
        }
        const ready = switch (self.phase) {
            .cold => true,
            .noop => self.turns == 120,
            .paint, .layout => self.done_advance,
            .inspection => self.turns == 20,
            .idle => ui_real_ns() - self.wall >= 200_000_000,
            .done => true,
        };
        if (!ready) return false;
        std.debug.print("HOST_PROFILE_STAGE {s} {d}\n", .{ @tagName(self.phase), ui_real_ns() - self.wall });
        var hash = std.hash.Wyhash.init(0);
        for (scene.items.items) |item| {
            hash.update(std.mem.asBytes(&item.node.id));
            hash.update(std.mem.asBytes(&item.bounds));
            hash.update(item.node.type);
            hash.update(item.node.style.backgroundColor);
        }
        self.records[self.count] = .{ .name = self.phase, .wallNs = ui_real_ns() - self.wall, .cpuNs = ui_cpu_ns() - self.cpu, .appTime = runtime.now(), .paints = paints - self.paints, .layouts = layouts - self.layouts, .native = stats, .quickjs = runtime.memory(), .sceneHash = hash.final(), .inspectionBytes = self.inspection_bytes };
        self.count += 1;
        self.phase = @fromBackingInt(@backingInt(self.phase) + 1);
        self.turns = 0;
        self.done_advance = false;
        self.wall = ui_real_ns();
        self.cpu = ui_cpu_ns();
        self.paints = paints;
        self.layouts = layouts;
        self.inspection_bytes = 0;
        if (self.phase != .done) return false;
        const json = try std.json.Stringify.valueAlloc(a, .{ .driver = driver, .driverStorageBytes = storage, .viewport = .{ .width = rl.getScreenWidth(), .height = rl.getScreenHeight(), .framebufferWidth = rl.getRenderWidth(), .framebufferHeight = rl.getRenderHeight(), .scale = rl.getWindowScaleDPI() }, .stages = self.records[0..self.count] }, .{});
        std.debug.print("HOST_PROFILE {s}\n", .{json});
        return true;
    }
};
