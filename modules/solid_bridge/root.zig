//! QuickJS host interface. This module owns no UI layout or drawing.
const std = @import("std");
const scheduling = @import("host_scheduler");
pub const app_clock = scheduling.clock;
var scheduler: scheduling.Scheduler = undefined;
var clock: app_clock.Clock = undefined;
var generation: u64 = 0;
var initialized = false;
var dispatching = false;
extern fn ui_real_ns() u64;
extern fn ui_cpu_ns() u64;
extern fn ui_timer_call(id: u64, timestamp: f64, once: c_int, raf: c_int) c_int;
extern fn ui_timer_release(id: u64) void;
extern fn ui_jobs() c_int;
extern fn ui_watchdog_start() void;
extern fn ui_watchdog_stop() void;
pub const Memory = extern struct { allocations: u64, frees: u64, live_count: u64, live_bytes: u64, high_count: u64, high_bytes: u64, roots: u64 };
extern fn ui_memory(*Memory) void;
extern fn ui_fail_allocations(c_int) void;
extern fn ui_probes_enabled() c_int;
extern fn ui_log_count() c_uint;
extern fn ui_log_dropped() c_uint;
extern fn ui_log_line(c_uint) [*:0]const u8;

export fn host_app_now() f64 {
    return app_clock.milliseconds(clock.now);
}
export fn host_controlled() c_int {
    return @intFromBool(clock.mode == .controlled);
}
export fn host_timer_add(ms: f64, kind: c_int) u64 {
    const delay = app_clock.fromMs(ms) catch return 0;
    return scheduler.schedule(clock.now, delay, if (kind == 1) delay else 0, kind == 2) catch 0;
}
export fn host_timer_cancel(id: u64) void {
    if (scheduler.cancel(id)) ui_timer_release(id);
}
fn take(now: u64, live: bool) !?scheduling.Record {
    const id = if (scheduler.next()) |r| r.id else 0;
    return scheduler.take(now, live) catch |err| {
        if (id != 0) ui_timer_release(id);
        return err;
    };
}
extern fn ui_init(source: [*]const u8, len: usize) c_int;
extern fn ui_init_driver(source: [*]const u8, len: usize) c_int;
extern fn ui_eval(code: [*:0]const u8, out: [*]u8, capacity: usize) c_int;
extern fn ui_eval_string(code: [*:0]const u8) ?[*:0]u8;
extern fn ui_free_string(value: [*:0]u8) void;
extern fn ui_destroy() void;
extern fn ui_reload() c_int;
extern fn ui_tick() c_int;
extern fn ui_next_timeout() f64;
extern fn ui_input(id: u32, text: [*:0]const u8) c_int;

pub const Runtime = struct {
    pub fn memory(_: *Runtime) Memory {
        var m: Memory = undefined;
        ui_memory(&m);
        return m;
    }
    pub fn logs(_: *Runtime, allocator: std.mem.Allocator) !struct { lines: [][]const u8, dropped: u32 } {
        const lines = try allocator.alloc([]const u8, ui_log_count());
        for (lines, 0..) |*line, i| line.* = std.mem.span(ui_log_line(@intCast(i)));
        return .{ .lines = lines, .dropped = ui_log_dropped() };
    }
    pub fn now(_: *Runtime) f64 {
        return app_clock.milliseconds(clock.now);
    }
    pub fn seconds(_: *Runtime) f64 {
        return app_clock.seconds(clock.now);
    }
    pub fn atFrame(_: *Runtime) bool {
        const index = clock.now * 60 / 1_000_000_000;
        return clock.now == (index * 1_000_000_000 + 59) / 60;
    }
    pub fn controlled(_: *Runtime) bool {
        return clock.mode == .controlled;
    }
    pub fn runtimeGeneration(_: *Runtime) u64 {
        return generation;
    }
    pub fn pending(_: *Runtime) usize {
        return scheduler.len;
    }
    pub fn nextDeadline(_: *Runtime) ?f64 {
        return if (scheduler.next()) |record| app_clock.milliseconds(record.at) else null;
    }
    pub fn due(_: *Runtime) bool {
        return if (scheduler.next()) |r| r.at <= clock.now else false;
    }
    pub fn jobsPending(_: *Runtime) bool {
        return ui_next_timeout() == 0;
    }
    pub fn schedulerMetrics(_: *Runtime) struct { active: usize, highWater: usize, capacity: usize, bytes: usize, fired: u64 } {
        return .{ .active = scheduler.len, .highWater = scheduler.high_water, .capacity = scheduling.capacity, .bytes = @sizeOf(scheduling.Scheduler), .fired = scheduler.fired };
    }
    pub fn target(_: *Runtime, delta_ms: f64) !u64 {
        if (clock.mode != .controlled) return error.ClockIsLive;
        return app_clock.add(clock.now, try app_clock.fromMs(delta_ms));
    }
    // One callback is one native commit turn. The host applies/acknowledges the
    // resulting patches before calling step again, including nested zero timers.
    pub fn step(_: *Runtime, target_ns: u64, motion: bool) !bool {
        if (dispatching) return error.ReentrantAdvance;
        dispatching = true;
        defer dispatching = false;
        if (target_ns < clock.now or target_ns > app_clock.horizon) return error.ClockOutOfRange;
        ui_watchdog_start();
        defer ui_watchdog_stop();
        if (ui_jobs() == 0) return error.JavaScriptJobFailed;
        var at = target_ns;
        if (scheduler.next()) |r| at = @min(at, r.at);
        if (motion) at = @min(at, try app_clock.nextFrame(clock.now));
        try clock.reach(@max(clock.now, at));
        if (try take(clock.now, false)) |r| {
            if (ui_timer_call(r.id, host_app_now(), @intFromBool(r.repeat == 0), @intFromBool(r.raf)) == 0) return error.JavaScriptCallbackFailed;
            return false;
        }
        return clock.now == target_ns;
    }
    pub fn sample(_: *Runtime) !void {
        if (scheduler.next()) |r| if (r.at <= clock.now) return;
        try clock.sample(ui_real_ns());
    }
    pub fn pointer(_: *Runtime, hovered: ?u32, active_id: ?u32, focused: ?u32) !void {
        var command: [128]u8 = undefined;
        const expression = try std.fmt.bufPrint(command[0 .. command.len - 1], "uiDispatchPointer({d},{d},{d})", .{ hovered orelse 0, active_id orelse 0, focused orelse 0 });
        command[expression.len] = 0;
        var result: [32]u8 = undefined;
        if (ui_eval(@ptrCast(expression.ptr), &result, result.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn viewport(_: *Runtime, width: i32, height: i32) !void {
        var command: [128]u8 = undefined;
        const expression = try std.fmt.bufPrint(command[0 .. command.len - 1], "globalThis.__uiViewport={{width:{d},height:{d}}}", .{ width, height });
        command[expression.len] = 0;
        var result: [32]u8 = undefined;
        if (ui_eval(@ptrCast(expression.ptr), &result, result.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn input(_: *Runtime, id: u32, text: [:0]const u8) !void {
        if (ui_input(id, text.ptr) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn acknowledge(_: *Runtime) !void {
        var ignored: [32]u8 = undefined;
        if (ui_eval("uiCommit()", &ignored, ignored.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn tick(_: *Runtime) !void {
        ui_watchdog_start();
        defer ui_watchdog_stop();
        if (ui_jobs() == 0) return error.JavaScriptJobFailed;
        if (clock.mode == .live) if (try take(clock.now, true)) |r| {
            if (ui_timer_call(r.id, host_app_now(), @intFromBool(r.repeat == 0), @intFromBool(r.raf)) == 0) return error.JavaScriptCallbackFailed;
        };
    }
    pub fn nextTimeout(_: *Runtime) f64 {
        if (clock.mode == .controlled) return -1;
        if (ui_next_timeout() == 0) return 0;
        const next = scheduler.next() orelse return -1;
        return app_clock.seconds(next.at -| clock.now);
    }
    pub fn init(source: []const u8) !Runtime {
        return initMode(source, .live);
    }
    pub fn initMode(source: []const u8, mode: app_clock.Mode) !Runtime {
        return initConfigured(source, mode, false);
    }
    pub fn initDriver(source: []const u8, mode: app_clock.Mode) !Runtime {
        return initConfigured(source, mode, true);
    }
    fn initConfigured(source: []const u8, mode: app_clock.Mode, driver: bool) !Runtime {
        if (initialized) return error.RuntimeAlreadyInitialized;
        scheduler = scheduling.Scheduler.init();
        clock = .{ .mode = mode, .origin = ui_real_ns() };
        generation = if (generation == 0) @max(1, ui_real_ns() & app_clock.horizon) else try app_clock.add(generation, 1);
        const result = if (driver) ui_init_driver(source.ptr, source.len) else ui_init(source.ptr, source.len);
        if (result < 0) return error.RuntimeAlreadyInitialized;
        if (result == 0) {
            ui_destroy();
            return error.JavaScriptInitializationFailed;
        }
        initialized = true;
        return .{};
    }
    pub fn deinit(_: *Runtime) void {
        ui_destroy();
        initialized = false;
        scheduler = scheduling.Scheduler.init();
    }
    pub fn changes(_: *Runtime) ![:0]u8 {
        const result = ui_eval_string("uiFrameChanges()") orelse return error.JavaScriptEvaluationFailed;
        return std.mem.span(result);
    }
    pub fn freeChanges(_: *Runtime, value: [:0]u8) void {
        ui_free_string(value.ptr);
    }
    pub fn click(_: *Runtime, id: u32) !void {
        var command: [64]u8 = undefined;
        const expression = try std.fmt.bufPrint(command[0 .. command.len - 1], "uiDispatchClick({d})", .{id});
        command[expression.len] = 0;
        var result: [32]u8 = undefined;
        if (ui_eval(@ptrCast(expression.ptr), &result, result.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn key(_: *Runtime, id: u32, key_name: []const u8) !void {
        var command: [128]u8 = undefined;
        const expression = try std.fmt.bufPrint(command[0 .. command.len - 1], "uiDispatchKey({d},\"{s}\")", .{ id, key_name });
        command[expression.len] = 0;
        var result: [32]u8 = undefined;
        if (ui_eval(@ptrCast(expression.ptr), &result, result.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn reload(_: *Runtime) bool {
        return ui_reload() != 0;
    }
};

fn expectJS(code: [*:0]const u8, expected: []const u8) !void {
    const result = ui_eval_string(code) orelse return error.JavaScriptEvaluationFailed;
    defer ui_free_string(result);
    try std.testing.expectEqualStrings(expected, std.mem.span(result));
}
fn advanceTest(runtime: *Runtime, ms: f64) !void {
    const at = try runtime.target(ms);
    var count: usize = 0;
    while (!try runtime.step(at, false)) {
        count += 1;
        if (count > 10000) return error.BudgetExceeded;
    }
}
test "real QuickJS timers settle jobs, rAF cancellation and controlled Date semantics" {
    var rt = try Runtime.initMode("globalThis.events=[];setTimeout(()=>{events.push('a');Promise.resolve().then(()=>events.push('job'));setTimeout(()=>events.push('nested'),0)},0);setTimeout(()=>events.push('b'),0);" ++ "let interval=setInterval(()=>{events.push('i');clearInterval(interval)},1);" ++ "let cancelled;requestAnimationFrame(t=>{events.push('raf:'+t);cancelAnimationFrame(cancelled);requestAnimationFrame(()=>events.push('next'))});cancelled=requestAnimationFrame(()=>events.push('cancelled'));", .controlled);
    defer rt.deinit();
    try advanceTest(&rt, 0);
    try expectJS("events.join(',')", "a,job,b,nested");
    try advanceTest(&rt, 17);
    try expectJS("events.join(',')", "a,job,b,nested,i,raf:16.666667");
    try advanceTest(&rt, 17);
    try expectJS("events.at(-1)", "next");
    try expectJS("new Date().constructor===Date", "true");
    try expectJS("[Date.now(),+new Date(),new Date(0).getTime(),Date.parse('1970-01-01T00:00:00Z'),Date()===new Date().toString(),new Date() instanceof Date,(()=>{class X extends Date{};return new X() instanceof X})()].join(',')", "1700000000034,1700000000034,0,0,true,true,true");
}
test "timer normalization, callback roots, failures and bounded jobs" {
    var rt = try Runtime.initMode("globalThis.n=0;", .controlled);
    defer rt.deinit();
    try expectJS("setTimeout((a)=>n=a,NaN,42); 'ok'", "ok");
    try advanceTest(&rt, 0);
    try expectJS("n", "42");
    try expectJS("(()=>{try{setTimeout('x',0)}catch(e){return e instanceof TypeError}})()", "true");
    try expectJS("let bad=setTimeout(()=>{n=7;throw Error('expected')},5);'ok'", "ok");
    try std.testing.expectError(error.JavaScriptCallbackFailed, advanceTest(&rt, 10));
    try std.testing.expectEqual(@as(f64, 5), rt.now());
    try expectJS("n", "7");
    try expectJS("for(let i=0;i<20000;i++){const id=setTimeout(()=>{},100);clearTimeout(id)};'done'", "done");
    try std.testing.expectEqual(@as(usize, 0), rt.pending());
    try expectJS("setTimeout(()=>{while(true){}},0);'armed'", "armed");
    try std.testing.expectError(error.JavaScriptCallbackFailed, advanceTest(&rt, 0));
}
test "VM allocation failure and disposal release roots exactly once" {
    var rt = try Runtime.initMode("globalThis.fn=()=>{};", .controlled);
    if (ui_probes_enabled() != 0) {
        ui_fail_allocations(1);
        var ignored: [16]u8 = undefined;
        try std.testing.expectEqual(@as(c_int, 0), ui_eval("setTimeout(fn,1)", &ignored, ignored.len));
        ui_fail_allocations(0);
        try std.testing.expectEqual(@as(usize, 0), rt.pending());
        try std.testing.expectEqual(@as(u64, 0), rt.memory().roots);
    }
    try expectJS("setTimeout(fn,100);setInterval(fn,10);requestAnimationFrame(fn);'ok'", "ok");
    if (ui_probes_enabled() != 0) try std.testing.expectEqual(@as(u64, 3), rt.memory().roots);
    rt.deinit();
    try std.testing.expectEqual(@as(u64, 0), rt.memory().roots);
    try std.testing.expectEqual(@as(u64, 0), rt.memory().live_bytes);
    var next = try Runtime.initMode("globalThis.x=0;", .controlled);
    defer next.deinit();
    try advanceTest(&next, 1000);
    try expectJS("x", "0");
}
test "matched schedule cancel and dispatch measurement against previous JS Map timers" {
    if (ui_probes_enabled() == 0) return;
    const legacy = "globalThis.__timers=new Map();let __timerId=0;globalThis.setTimeout=(fn,ms=0,...args)=>{const id=++__timerId;__timers.set(id,{fn:()=>fn(...args),at:__nativeNow()+Math.max(0,Number(ms)||0)});return id};globalThis.clearTimeout=id=>__timers.delete(id);globalThis.__pumpTimers=()=>{const now=__nativeNow();for(const [id,t] of __timers){if(t.at>now)continue;__timers.delete(id);t.fn()}};";
    for ([_]bool{ true, false }) |old| {
        var rt = try Runtime.initMode(if (old) legacy else "", .controlled);
        const before = rt.memory();
        const wall = ui_real_ns();
        const cpu = ui_cpu_ns();
        try expectJS("globalThis.hits=0;globalThis.fn=()=>hits++;for(let i=0;i<200000;i++){const id=setTimeout(fn,100);clearTimeout(id)};'ok'", "ok");
        for (0..10000) |_| {
            try expectJS("setTimeout(fn,0);'ok'", "ok");
            if (old) try expectJS("__pumpTimers();'ok'", "ok") else try advanceTest(&rt, 0);
        }
        const elapsed = ui_real_ns() - wall;
        const used_cpu = ui_cpu_ns() - cpu;
        const after = rt.memory();
        try expectJS("hits", "10000");
        std.debug.print("CLOCK_BENCH {s} wall_ns={d} cpu_ns={d} allocs={d} frees={d} live_count={d} live_bytes={d} high_count={d} high_bytes={d} scheduler_bytes={d}\n", .{ if (old) "previous-js-map" else "zig-scheduler", elapsed, used_cpu, after.allocations - before.allocations, after.frees - before.frees, after.live_count, after.live_bytes, after.high_count, after.high_bytes, @sizeOf(scheduling.Scheduler) });
        rt.deinit();
        try std.testing.expectEqual(@as(u64, 0), rt.memory().live_bytes);
    }
}
