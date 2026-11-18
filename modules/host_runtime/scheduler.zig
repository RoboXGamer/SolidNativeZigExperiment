const std = @import("std");
pub const clock = @import("clock.zig");
pub const capacity = 4096;
const none = std.math.maxInt(u16);
pub const Record = struct { id: u64 = 0, at: u64 = 0, repeat: u64 = 0, sequence: u64 = 0, raf: bool = false, after_frame: bool = false, heap: u16 = none };
pub const Scheduler = struct {
    slots: [capacity]Record = @splat(.{}),
    heap: [capacity]u16 = undefined,
    free: [capacity]u16 = undefined,
    len: usize = 0,
    free_len: usize = capacity,
    sequence: u64 = 0,
    ids: u64 = 0,
    fired: u64 = 0,
    high_water: usize = 0,
    frame_at: ?u64 = null,
    pub fn init() Scheduler {
        var s: Scheduler = .{};
        for (&s.free, 0..) |*slot, i| slot.* = @intCast(capacity - i - 1);
        return s;
    }
    fn before(self: *const Scheduler, a: u16, b: u16) bool {
        const x = self.slots[a];
        const y = self.slots[b];
        if (x.at != y.at) return x.at < y.at;
        if (x.after_frame != y.after_frame) return !x.after_frame;
        if (x.raf != y.raf) return !x.raf;
        return x.sequence < y.sequence;
    }
    fn swap(self: *Scheduler, a: usize, b: usize) void {
        std.mem.swap(u16, &self.heap[a], &self.heap[b]);
        self.slots[self.heap[a]].heap = @intCast(a);
        self.slots[self.heap[b]].heap = @intCast(b);
    }
    fn up(self: *Scheduler, start: usize) void {
        var i = start;
        while (i > 0) {
            const p = (i - 1) / 2;
            if (!self.before(self.heap[i], self.heap[p])) break;
            self.swap(i, p);
            i = p;
        }
    }
    fn down(self: *Scheduler, start: usize) void {
        var i = start;
        while (i * 2 + 1 < self.len) {
            var child = i * 2 + 1;
            if (child + 1 < self.len and self.before(self.heap[child + 1], self.heap[child])) child += 1;
            if (!self.before(self.heap[child], self.heap[i])) break;
            self.swap(child, i);
            i = child;
        }
    }
    fn insert(self: *Scheduler, slot: u16) void {
        self.heap[self.len] = slot;
        self.slots[slot].heap = @intCast(self.len);
        self.len += 1;
        self.up(self.len - 1);
    }
    fn remove(self: *Scheduler, slot: u16) void {
        const pos = self.slots[slot].heap;
        self.len -= 1;
        if (pos < self.len) {
            const moved = self.heap[self.len];
            self.heap[pos] = moved;
            self.slots[moved].heap = pos;
            self.up(pos);
            self.down(self.slots[moved].heap);
        }
        self.slots[slot].heap = none;
    }
    pub fn schedule(self: *Scheduler, now: u64, delay: u64, repeat: u64, raf: bool) !u64 {
        if (self.free_len == 0) return error.TimerLimit;
        if (self.ids >= (clock.horizon - capacity) / capacity or self.sequence == std.math.maxInt(u64)) return error.TimerIdExhausted;
        const at = if (raf) try clock.nextFrame(now) else try clock.add(now, delay);
        self.free_len -= 1;
        const slot = self.free[self.free_len];
        self.ids += 1;
        self.sequence += 1;
        const id = self.ids * capacity + slot;
        self.slots[slot] = .{ .id = id, .at = at, .repeat = repeat, .raf = raf, .sequence = self.sequence, .after_frame = !raf and self.frame_at == now };
        self.insert(slot);
        self.high_water = @max(self.high_water, self.len);
        return id;
    }
    pub fn cancel(self: *Scheduler, id: u64) bool {
        const slot: u16 = @intCast(id % capacity);
        if (id == 0 or self.slots[slot].id != id) return false;
        self.remove(slot);
        self.slots[slot].id = 0;
        self.free[self.free_len] = slot;
        self.free_len += 1;
        return true;
    }
    pub fn next(self: *const Scheduler) ?Record {
        return if (self.len == 0) null else self.slots[self.heap[0]];
    }
    // Rearm before invoking JS, allowing self-cancellation. Live repeats coalesce;
    // controlled repeats preserve the previous deadline and catch up within budgets.
    pub fn take(self: *Scheduler, now: u64, live: bool) !?Record {
        const r = self.next() orelse return null;
        if (r.at > now) return null;
        if (r.raf) self.frame_at = now;
        if (r.repeat == 0) {
            _ = self.cancel(r.id);
        } else {
            const slot: u16 = @intCast(r.id % capacity);
            const next_at = clock.add(if (live) now else r.at, r.repeat) catch |err| {
                _ = self.cancel(r.id);
                return err;
            };
            self.remove(slot);
            self.slots[slot].at = next_at;
            self.insert(slot);
        }
        self.fired += 1;
        return r;
    }
};

test "stable deadlines, indexed cancellation, self-cancel and stale handles" {
    var s = Scheduler.init();
    const a = try s.schedule(0, 350_000_000, 0, false);
    const b = try s.schedule(0, 350_000_000, 1_000_000, false);
    try std.testing.expectEqual(@as(?Record, null), try s.take(349_000_000, false));
    try std.testing.expectEqual(a, (try s.take(350_000_000, false)).?.id);
    const c = try s.schedule(350_000_000, 0, 0, false);
    try std.testing.expect(!s.cancel(a));
    try std.testing.expectEqual(b, (try s.take(350_000_000, false)).?.id);
    try std.testing.expect(s.cancel(b));
    try std.testing.expectEqual(c, (try s.take(350_000_000, false)).?.id);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}
test "bounded records and rollover" {
    var s = Scheduler.init();
    for (0..capacity) |_| _ = try s.schedule(0, 1, 0, false);
    try std.testing.expectError(error.TimerLimit, s.schedule(0, 0, 0, false));
    while (s.next()) |r| _ = s.cancel(r.id);
    s.ids = clock.horizon;
    try std.testing.expectError(error.TimerIdExhausted, s.schedule(0, 0, 0, false));
}
test "live coalescing, controlled catch-up and rAF batch isolation" {
    var live = Scheduler.init();
    const id = try live.schedule(0, 1, 1, false);
    _ = try live.take(100, true);
    try std.testing.expectEqual(@as(u64, 101), live.next().?.at);
    _ = live.cancel(id);
    var controlled = Scheduler.init();
    _ = try controlled.schedule(0, 1, 1, false);
    for (1..101) |n| try std.testing.expectEqual(@as(u64, n), (try controlled.take(100, false)).?.at);
    var s = Scheduler.init();
    const a = try s.schedule(0, 0, 0, true);
    const b = try s.schedule(0, 0, 0, true);
    const at = (try clock.nextFrame(0));
    try std.testing.expectEqual(a, (try s.take(at, false)).?.id);
    const nested = try s.schedule(at, 0, 0, false);
    try std.testing.expectEqual(b, (try s.take(at, false)).?.id);
    try std.testing.expectEqual(nested, (try s.take(at, false)).?.id);
}
