//! Exact requested-byte counters around a native allocator. OS page/driver/GPU
//! allocation sizes are deliberately not inferred from these counters.
const std = @import("std");
const A = std.mem.Alignment;
pub const Stats = struct { allocations: u64 = 0, frees: u64 = 0, live_count: usize = 0, live_bytes: usize = 0, high_count: usize = 0, high_bytes: usize = 0 };
pub const Accounting = struct {
    backing: std.mem.Allocator = std.heap.page_allocator,
    stats: Stats = .{},
    pub fn allocator(self: *Accounting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .free = free, .resize = resize, .remap = remap } };
    }
    fn changed(self: *Accounting, before: usize, after: usize) void {
        self.stats.live_bytes = self.stats.live_bytes - before + after;
        self.stats.high_bytes = @max(self.stats.high_bytes, self.stats.live_bytes);
    }
    fn alloc(ptr: *anyopaque, len: usize, alignment: A, ret: usize) ?[*]u8 {
        const self: *Accounting = @ptrCast(@alignCast(ptr));
        const result = self.backing.rawAlloc(len, alignment, ret) orelse return null;
        self.stats.allocations += 1;
        self.stats.live_count += 1;
        self.stats.high_count = @max(self.stats.high_count, self.stats.live_count);
        self.changed(0, len);
        return result;
    }
    fn free(ptr: *anyopaque, bytes: []u8, alignment: A, ret: usize) void {
        const self: *Accounting = @ptrCast(@alignCast(ptr));
        self.backing.rawFree(bytes, alignment, ret);
        self.stats.frees += 1;
        self.stats.live_count -= 1;
        self.changed(bytes.len, 0);
    }
    fn resize(ptr: *anyopaque, bytes: []u8, alignment: A, len: usize, ret: usize) bool {
        const self: *Accounting = @ptrCast(@alignCast(ptr));
        if (!self.backing.rawResize(bytes, alignment, len, ret)) return false;
        self.changed(bytes.len, len);
        return true;
    }
    fn remap(ptr: *anyopaque, bytes: []u8, alignment: A, len: usize, ret: usize) ?[*]u8 {
        const self: *Accounting = @ptrCast(@alignCast(ptr));
        const p = self.backing.rawRemap(bytes, alignment, len, ret) orelse return null;
        self.changed(bytes.len, len);
        return p;
    }
};
