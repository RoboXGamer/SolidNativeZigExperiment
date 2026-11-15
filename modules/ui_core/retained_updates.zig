//! Retained phase inputs and read dependencies. Layout builds the index once;
//! subsequent updates visit dirty identities and their actual dependants.
const std = @import("std");
const ui = @import("scene.zig");
const styles = @import("style.zig");
const inputs = @import("frame_inputs.zig");
const paint_count = @typeInfo(styles.PaintStyle).@"struct".field_names.len;
const interaction_count = @typeInfo(styles.InteractionStyle).@"struct".field_names.len;
pub const Fields = std.StaticBitSet(paint_count + interaction_count);
pub const PaintFields = std.StaticBitSet(paint_count);
pub const Overlay = struct { fields: PaintFields = .empty, style: styles.PaintStyle = .{} };
pub const Sample = struct { id: u32, overlay: Overlay = .{} };
pub const Reads = struct { fields: Fields = .empty };
pub fn parentValue(reads: *Reads, parent: *const ui.Node, comptime field: []const u8) @FieldType(styles.Style, field) {
    inline for (@typeInfo(styles.PaintStyle).@"struct".field_names, 0..) |name, i| {
        if (comptime std.mem.eql(u8, field, name)) reads.fields.set(i);
    }
    inline for (@typeInfo(styles.InteractionStyle).@"struct".field_names, 0..) |name, i| {
        if (comptime std.mem.eql(u8, field, name)) reads.fields.set(paint_count + i);
    }
    return @field(parent.style, field);
}
pub const Source = struct {
    parent: ?u32,
    paint: inputs.PaintInputs,
    interaction: inputs.InteractionInputs,
    motion: styles.MotionStyle,
    pub fn from(node: anytype, parent: ?u32) Source {
        return .{ .parent = parent, .paint = inputs.select(inputs.PaintInputs, node), .interaction = inputs.select(inputs.InteractionInputs, node), .motion = styles.select(styles.MotionStyle, node.style) };
    }
};

pub const Work = struct { evaluated: usize = 0, paint: usize = 0, interaction: usize = 0, motion: usize = 0, instances: usize = 0 };
pub const Result = struct { paint: bool = false, interaction: bool = false, work: Work = .{} };
pub const Observer = struct {
    context: *anyopaque,
    style: *const fn (*anyopaque, u32, styles.Style, styles.Style) anyerror!void,
};
const Key = struct { parent: u32, field: usize };
const Watchers = std.AutoHashMapUnmanaged(u32, void);
const Record = struct {
    node: *ui.Node,
    instances: std.ArrayList(*ui.Node) = .empty,
    source: Source,
    reads: Reads,
    depth: usize = 0,
    paint_storage: ?std.heap.ArenaAllocator = null,
    interaction_storage: ?std.heap.ArenaAllocator = null,
    motion_storage: ?std.heap.ArenaAllocator = null,
    overlay: Overlay = .{},
    fn deinit(self: *Record, a: std.mem.Allocator) void {
        self.instances.deinit(a);
        if (self.paint_storage) |*storage| storage.deinit();
        if (self.interaction_storage) |*storage| storage.deinit();
        if (self.motion_storage) |*storage| storage.deinit();
    }
};
const Pending = struct {
    paint: bool = false,
    interaction: bool = false,
    motion: bool = false,
    direct_paint: bool = false,
    direct_interaction: bool = false,
    direct_motion: bool = false,
    fn merge(self: *Pending, other: Pending) void {
        inline for (@typeInfo(Pending).@"struct".field_names) |name| @field(self, name) = @field(self, name) or @field(other, name);
    }
};
const Stage = struct {
    candidate: ui.Node,
    source: Source,
    reads: Reads,
    pending: Pending,
    overlay: Overlay = .{},
    target: styles.Style,
    pixel_change: bool = false,
    paint_storage: ?std.heap.ArenaAllocator = null,
    interaction_storage: ?std.heap.ArenaAllocator = null,
    motion_storage: ?std.heap.ArenaAllocator = null,
    fn deinit(self: *Stage) void {
        if (self.paint_storage) |*storage| storage.deinit();
        if (self.interaction_storage) |*storage| storage.deinit();
        if (self.motion_storage) |*storage| storage.deinit();
    }
};
fn clone(a: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    var result = value;
    switch (@typeInfo(@TypeOf(value))) {
        .@"struct" => inline for (@typeInfo(@TypeOf(value)).@"struct".field_names) |name| {
            @field(result, name) = try clone(a, @field(value, name));
        },
        .pointer => |p| if (p.size == .slice) {
            result = try a.dupe(p.child, value);
        },
        .optional => if (value) |present| {
            result = try clone(a, present);
        },
        else => {},
    }
    return result;
}
fn changedFields(before: styles.Style, after: styles.Style) Fields {
    var fields: Fields = .empty;
    inline for (@typeInfo(styles.PaintStyle).@"struct".field_names, 0..) |name, i| if (!inputs.equal(@field(before, name), @field(after, name))) {
        fields.set(i);
    };
    inline for (@typeInfo(styles.InteractionStyle).@"struct".field_names, 0..) |name, i| if (!inputs.equal(@field(before, name), @field(after, name))) {
        fields.set(paint_count + i);
    };
    return fields;
}
pub const Index = struct {
    allocator: ?std.mem.Allocator = null,
    records: std.AutoHashMapUnmanaged(u32, Record) = .empty,
    watchers: std.AutoHashMapUnmanaged(Key, Watchers) = .empty,
    last_work: Work = .{},
    pub fn deinit(self: *Index) void {
        const a = self.allocator orelse return;
        var records = self.records.valueIterator();
        while (records.next()) |record| record.deinit(a);
        var watchers = self.watchers.valueIterator();
        while (watchers.next()) |set| set.deinit(a);
        self.records.deinit(a);
        self.watchers.deinit(a);
        self.* = .{};
    }
    fn collect(self: *Index, scene: *ui.Scene, node: *ui.Node, visited: *std.AutoHashMapUnmanaged(usize, void)) anyerror!void {
        const a = self.allocator.?;
        const seen = try visited.getOrPut(a, @intFromPtr(node));
        if (seen.found_existing) return;
        const entry = try self.records.getOrPut(a, node.id);
        if (!entry.found_existing) {
            const canonical = if (scene.find(node.id)) |item| @constCast(item.node) else node;
            entry.value_ptr.* = .{ .node = canonical, .source = canonical.phase_source orelse Source.from(canonical.*, if (scene.find(node.id)) |item| item.parent_id else null), .reads = canonical.parent_reads };
        }
        try entry.value_ptr.instances.append(a, node);
        for (node.children) |*child| try self.collect(scene, child, visited);
    }
    pub fn rebuild(self: *Index, scene: *ui.Scene) !void {
        const a = scene.arena.child_allocator;
        var next = Index{ .allocator = a };
        errdefer next.deinit();
        var visited: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer visited.deinit(a);
        try next.collect(scene, scene.root, &visited);
        for (scene.items.items) |item| try next.collect(scene, @constCast(item.node), &visited);
        var entries = next.records.iterator();
        while (entries.next()) |entry| {
            var parent = entry.value_ptr.source.parent;
            while (parent) |id| {
                entry.value_ptr.depth += 1;
                if (entry.value_ptr.depth > 256) return error.CyclicDependency;
                parent = (next.records.get(id) orelse return error.MissingDependencyParent).source.parent;
            }
            if (entry.value_ptr.source.parent) |id| {
                var fields = entry.value_ptr.reads.fields.iterator(.{});
                while (fields.next()) |field| try next.addWatcher(.{ .parent = id, .field = field }, entry.key_ptr.*);
            }
        }
        // A layout resample can replace node aliases while phase-owned strings
        // remain live. Transfer their storage to the rebuilt index.
        entries = next.records.iterator();
        while (entries.next()) |entry| if (self.records.getPtr(entry.key_ptr.*)) |previous| {
            entry.value_ptr.paint_storage = previous.paint_storage;
            previous.paint_storage = null;
            entry.value_ptr.interaction_storage = previous.interaction_storage;
            previous.interaction_storage = null;
            entry.value_ptr.motion_storage = previous.motion_storage;
            previous.motion_storage = null;
            entry.value_ptr.overlay = previous.overlay;
        };
        self.deinit();
        self.* = next;
    }
    fn addWatcher(self: *Index, key: Key, id: u32) !void {
        const entry = try self.watchers.getOrPut(self.allocator.?, key);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.put(self.allocator.?, id, {});
    }
    fn less(self: *Index, left: u32, right: u32) std.math.Order {
        const order = std.math.order(self.records.get(left).?.depth, self.records.get(right).?.depth);
        return if (order == .eq) std.math.order(left, right) else order;
    }
    const Queue = std.PriorityQueue(u32, *Index, less);
    fn enqueue(self: *Index, a: std.mem.Allocator, queue: *Queue, pending: *std.AutoHashMapUnmanaged(u32, Pending), id: u32, flags: Pending) !void {
        if (!self.records.contains(id)) return; // Suppressed boxes have no pixels.
        const entry = try pending.getOrPut(a, id);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
            try queue.push(a, id);
        }
        entry.value_ptr.merge(flags);
    }
    pub fn update(self: *Index, scene: *ui.Scene, tree: ?*const ui.Tree, samples: []const Sample, a: std.mem.Allocator, observer: ?Observer) !Result {
        var result: Result = .{};
        if ((tree == null or tree.?.dirty.items.len == 0) and samples.len == 0) {
            self.last_work = .{};
            return result;
        }
        var queue = Queue.initContext(self);
        defer queue.deinit(a);
        var pending: std.AutoHashMapUnmanaged(u32, Pending) = .empty;
        defer pending.deinit(a);
        var staged: std.AutoHashMapUnmanaged(u32, Stage) = .empty;
        defer {
            var values = staged.valueIterator();
            while (values.next()) |stage| stage.deinit();
            staged.deinit(a);
        }
        var overlays: std.AutoHashMapUnmanaged(u32, Overlay) = .empty;
        defer overlays.deinit(a);
        for (samples) |sample| {
            try overlays.put(a, sample.id, sample.overlay);
            try self.enqueue(a, &queue, &pending, sample.id, .{ .paint = true });
        }
        if (tree) |source_tree| for (source_tree.dirty.items) |dirty| {
            if (dirty.paint or dirty.interaction or dirty.motion) try self.enqueue(a, &queue, &pending, dirty.id, .{ .paint = dirty.paint or dirty.motion, .interaction = dirty.interaction, .motion = dirty.motion, .direct_paint = dirty.paint, .direct_interaction = dirty.interaction, .direct_motion = dirty.motion });
        };
        while (queue.pop()) |id| {
            const record = self.records.get(id).?;
            const flags = pending.get(id).?;
            var stage = Stage{ .candidate = record.node.*, .source = record.source, .reads = record.reads, .pending = flags, .target = record.node.style, .overlay = overlays.get(id) orelse if (tree != null) .{} else record.overlay };
            errdefer stage.deinit();
            if (if (tree) |t| t.nodes.get(id) else null) |entry| if (std.mem.eql(u8, entry.node.type, record.node.type)) {
                if (flags.direct_paint) stage.source.paint = inputs.select(inputs.PaintInputs, entry.node);
                if (flags.direct_interaction) stage.source.interaction = inputs.select(inputs.InteractionInputs, entry.node);
                if (flags.direct_motion) stage.source.motion = styles.select(styles.MotionStyle, entry.node.style);
            };
            const parent: *const ui.Node = if (record.source.parent) |pid| if (staged.getPtr(pid)) |s| &s.candidate else self.records.get(pid).?.node else &stage.candidate;
            if (flags.motion) {
                stage.motion_storage = std.heap.ArenaAllocator.init(self.allocator.?);
                stage.source.motion = try clone(stage.motion_storage.?.allocator(), stage.source.motion);
                styles.assign(&stage.candidate.style, stage.source.motion);
                result.work.motion += 1;
            }
            if (flags.paint) {
                stage.paint_storage = std.heap.ArenaAllocator.init(self.allocator.?);
                const storage = stage.paint_storage.?.allocator();
                stage.source.paint = try clone(storage, stage.source.paint);
                inputs.setPaint(&stage.candidate, stage.source.paint);
                var reads = try scene.resolveRetainedPaint(&stage.candidate, parent, storage);
                stage.target = stage.candidate.style;
                if (stage.overlay.fields.count() > 0) {
                    // Retain the authored read edges while an animation masks a
                    // value; completing it must restore current inheritance.
                    stage.overlay = try clone(storage, stage.overlay);
                    inputs.setPaint(&stage.candidate, stage.source.paint);
                    inline for (@typeInfo(styles.PaintStyle).@"struct".field_names, 0..) |name, i| if (stage.overlay.fields.isSet(i)) {
                        @field(stage.candidate.style, name) = @field(stage.overlay.style, name);
                    };
                    const animated_reads = try scene.resolveRetainedPaint(&stage.candidate, parent, storage);
                    reads.fields.setUnion(animated_reads.fields);
                }
                inline for (0..paint_count) |i| stage.reads.fields.setValue(i, reads.fields.isSet(i));
                styles.assign(&stage.candidate.style, try clone(storage, styles.select(styles.PaintStyle, stage.candidate.style)));
                stage.pixel_change = !inputs.equal(styles.select(styles.PaintStyle, record.node.style), styles.select(styles.PaintStyle, stage.candidate.style)) or record.node.readOnly != stage.candidate.readOnly or record.node.readWrite != stage.candidate.readWrite or record.node.popoverOpen != stage.candidate.popoverOpen;
                result.paint = result.paint or stage.pixel_change;
                result.work.paint += 1;
            }
            if (flags.interaction) {
                stage.interaction_storage = std.heap.ArenaAllocator.init(self.allocator.?);
                const storage = stage.interaction_storage.?.allocator();
                stage.source.interaction = try clone(storage, stage.source.interaction);
                inputs.setInteraction(&stage.candidate, stage.source.interaction);
                const saved = stage.candidate.style;
                const reads = try scene.inheritWithAllocator(&stage.candidate, parent, storage);
                const effective = try clone(storage, inputs.select(inputs.InteractionInputs, stage.candidate));
                stage.candidate.style = saved;
                inputs.setInteraction(&stage.candidate, effective);
                inline for (paint_count..paint_count + interaction_count) |i| stage.reads.fields.setValue(i, reads.fields.isSet(i));
                result.interaction = true;
                result.work.interaction += 1;
            }
            const changed = changedFields(record.node.style, stage.candidate.style);
            var fields = changed.iterator(.{});
            while (fields.next()) |field| if (self.watchers.get(.{ .parent = id, .field = field })) |watchers| {
                var ids = watchers.keyIterator();
                while (ids.next()) |dependent| try self.enqueue(a, &queue, &pending, dependent.*, .{ .paint = field < paint_count, .interaction = field >= paint_count });
            };
            try staged.put(a, id, stage);
            result.work.evaluated += 1;
        }
        // Add replacement edges before touching retained values. On allocation
        // failure, remove only newly added edges and leave the old scene intact.
        var added: std.ArrayList(struct { key: Key, id: u32 }) = .empty;
        defer added.deinit(a);
        try added.ensureTotalCapacity(a, staged.count() * Fields.bit_length);
        errdefer for (added.items) |edge| {
            _ = self.watchers.getPtr(edge.key).?.remove(edge.id);
        };
        var stages = staged.iterator();
        while (stages.next()) |entry| {
            const record = self.records.get(entry.key_ptr.*).?;
            if (record.source.parent) |pid| {
                var fields = entry.value_ptr.reads.fields.iterator(.{});
                while (fields.next()) |field| if (!record.reads.fields.isSet(field)) {
                    const key = Key{ .parent = pid, .field = field };
                    try self.addWatcher(key, entry.key_ptr.*);
                    added.appendAssumeCapacity(.{ .key = key, .id = entry.key_ptr.* });
                };
            }
            if (entry.value_ptr.pending.paint) if (observer) |notify| try notify.style(notify.context, entry.key_ptr.*, record.node.style, entry.value_ptr.target);
        }
        stages = staged.iterator();
        while (stages.next()) |entry| {
            const record = self.records.getPtr(entry.key_ptr.*).?;
            const stage = entry.value_ptr;
            if (record.source.parent) |pid| {
                var fields = record.reads.fields.iterator(.{});
                while (fields.next()) |field| if (!stage.reads.fields.isSet(field)) {
                    _ = self.watchers.getPtr(.{ .parent = pid, .field = field }).?.remove(entry.key_ptr.*);
                };
            }
            for (record.instances.items) |node| {
                if (stage.pending.paint) {
                    inputs.setPaint(node, inputs.select(inputs.PaintInputs, stage.candidate));
                }
                if (stage.pending.interaction) inputs.setInteraction(node, inputs.select(inputs.InteractionInputs, stage.candidate));
                if (stage.pending.motion) styles.assign(&node.style, stage.source.motion);
                node.phase_source = stage.source;
                node.parent_reads = stage.reads;
                result.work.instances += 1;
            }
            record.source = stage.source;
            record.reads = stage.reads;
            record.overlay = stage.overlay;
            if (stage.paint_storage) |storage| {
                if (record.paint_storage) |*old| old.deinit();
                record.paint_storage = storage;
                stage.paint_storage = null;
            }
            if (stage.interaction_storage) |storage| {
                if (record.interaction_storage) |*old| old.deinit();
                record.interaction_storage = storage;
                stage.interaction_storage = null;
            }
            if (stage.motion_storage) |storage| {
                if (record.motion_storage) |*old| old.deinit();
                record.motion_storage = storage;
                stage.motion_storage = null;
            }
        }
        self.last_work = result.work;
        return result;
    }
};
