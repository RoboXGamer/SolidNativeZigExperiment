const std = @import("std");
const ui = @import("root.zig");
const a = std.testing.allocator;
const initial =
    \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"width":300,"color":"red"},"children":[2]},{"id":2,"type":"text","text":"hello world","style":{"fontSize":16,"fontWeightCss":"bolder","borderColor":"currentColor"}}]}
;
var measurements: usize = 0;
test "grid intrinsic height derives column count from CSS tracks" {
    var scene = try ui.Scene.init(a,
        \\{"id":1,"type":"root","children":[{"id":2,"type":"div","style":{"display":"grid","gridTemplateColumnsCss":"50px 50px"},"children":[{"id":3,"type":"div","style":{"height":10}},{"id":4,"type":"div","style":{"height":10}},{"id":5,"type":"div","style":{"height":10}}]}]}
    , 100, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 20), scene.naturalHeight(scene.find(2).?.node));
}
fn measure(_: ?*anyopaque, content: []const u8, size: f32) ui.Metrics {
    measurements += 1;
    return .{ .width = @as(f32, @floatFromInt(content.len)) * size / 2, .height = size, .ascent = size * 0.8 };
}
test "native phase deltas preserve geometry and do not measure on paint or interaction updates" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(initial);
    var scene = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
    defer scene.deinit();
    const bounds = scene.find(2).?.bounds;
    const before = measurements;
    const geometry_revision = tree.revisions.layout;
    const cursor = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"interaction":{"hovered":true,"style":{"cursor":"pointer"}}}]}
    );
    try std.testing.expect(cursor.state and cursor.cursor and !cursor.paint and !cursor.layout);
    const retained_node = scene.find(2).?.node;
    const interaction = try scene.updateInputs(&tree, a, null);
    try std.testing.expectEqual(@as(usize, 1), interaction.work.evaluated);
    try std.testing.expect(retained_node == scene.find(2).?.node);
    try std.testing.expectEqualStrings("pointer", scene.find(2).?.node.style.cursor);
    try std.testing.expect(scene.find(2).?.node.hovered);
    const paint = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"blue","opacityCss":"0.6","outlineWidth":2,"outlineStyle":"solid"}}}]}
    );
    try std.testing.expect(paint.paint and !paint.layout);
    const before_layout = @import("style.zig").select(@import("style.zig").LayoutStyle, scene.find(2).?.node.style);
    _ = try scene.updateInputs(&tree, a, null);
    try std.testing.expect(ui.frame_inputs.equal(before_layout, @import("style.zig").select(@import("style.zig").LayoutStyle, scene.find(2).?.node.style)));
    try std.testing.expectEqualStrings("blue", scene.find(2).?.node.style.color);
    try std.testing.expectEqualStrings("blue", scene.find(2).?.node.style.borderColor);
    try std.testing.expectEqual(@as(f32, 0.6), scene.find(1).?.node.style.opacity);
    try std.testing.expectEqual(@as(f32, 2), scene.find(1).?.node.style.outlineWidth);
    try std.testing.expectEqual(bounds, scene.find(2).?.bounds);
    try std.testing.expectEqual(before, measurements);
    try std.testing.expectEqual(geometry_revision, tree.revisions.layout);
    try std.testing.expectEqualStrings("hello world", scene.find(2).?.node.text);
    const geometry = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"layout":{"type":"text","text":"a much longer line","style":{"fontSize":24}}}]}
    );
    try std.testing.expect(geometry.layout and geometry.paint);
    try std.testing.expect(tree.revisions.layout > geometry_revision);
    const next = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
    scene.deinit();
    scene = next;
    try std.testing.expect(measurements > before);
}
test "paint transitions do not invoke the layout measurer" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(initial);
    var old = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
    defer old.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"blue"}},"motion":{"transition":"color 1s linear"}}]}
    );
    var next = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
    defer next.deinit();
    var timeline = ui.transitions.Timeline.init(a);
    defer timeline.deinit();
    try timeline.retarget(&old, &next, 0);
    try std.testing.expect(timeline.active());
    try std.testing.expect(!timeline.needsLayout());
    const before = measurements;
    const bounds = next.find(2).?.bounds;
    try timeline.apply(&next, 0.5);
    try std.testing.expectEqual(before, measurements);
    try std.testing.expectEqual(bounds, next.find(2).?.bounds);
    try timeline.apply(&next, 2);
    try std.testing.expect(!timeline.active());
}
test "phase batches reject missing and duplicate identities atomically" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(initial);
    const revision = tree.revisions;
    try std.testing.expectError(error.UnknownNode, tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"paint":{"style":{"color":"blue"}}},{"id":99,"interaction":{}}]}
    ));
    try std.testing.expectEqual(revision, tree.revisions);
    try std.testing.expectError(error.DuplicateNode, tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"interaction":{}},{"id":2,"paint":{}}]}
    ));
    try std.testing.expectEqual(revision, tree.revisions);
}

test "visibility ownership survives interaction updates and popovers invalidate paint" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"visibility":"hidden"},"children":[2]},{"id":2,"type":"div","style":{"visibility":"visible","interactionSpecified":1}}]}
    );
    var scene = try ui.Scene.fromTree(&tree, 300, 200);
    defer scene.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"interaction":{"style":{"cursor":"help"}}}]}
    );
    const cursor = try scene.updateInputs(&tree, a, null);
    try std.testing.expect(!cursor.paint);
    try std.testing.expectEqualStrings("visible", scene.find(2).?.node.style.visibility);
    try std.testing.expect(scene.find(2).?.node.style.interactionSpecified & 1 != 0);
    const changed = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"paint":{"popoverOpen":true,"visibilitySpecified":true}}]}
    );
    try std.testing.expect(changed.paint and !changed.layout);
    const popup = try scene.updateInputs(&tree, a, null);
    try std.testing.expect(popup.paint);
    try std.testing.expect(scene.find(2).?.node.popoverOpen);
}
test "paint refreshes own data and scroll offsets do not accumulate" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"width":200,"height":60,"overflow":"scroll"},"children":[2]},{"id":2,"type":"div","style":{"width":100,"height":300}}]}
    );
    var scene = try ui.Scene.fromTree(&tree, 200, 100);
    defer scene.deinit();
    var offsets = std.AutoHashMap(u32, ui.ScrollOffset).init(a);
    defer offsets.deinit();
    try offsets.put(1, .{ .y = 10 });
    scene.applyScrollOffsets(&offsets);
    const y = scene.find(2).?.bounds.y;
    scene.applyScrollOffsets(&offsets);
    try std.testing.expectEqual(y, scene.find(2).?.bounds.y);
    for (0..50) |_| {
        _ = try tree.applyChanges(
            \\{"root":1,"updates":[{"id":1,"paint":{"style":{"backgroundColor":"blue"}}}]}
        );
        _ = try scene.updateInputs(&tree, a, null);
        try std.testing.expectEqual(y, scene.find(2).?.bounds.y);
    }
}

test "real computed CSS batches match cold scene layout and effective styles" {
    const Fixture = struct { name: []const u8, layout: bool, paint: bool, patch: []const u8, cold: []const u8 };
    const parsed = try std.json.parseFromSlice([]const Fixture, a, @embedFile("fixtures/css-dependencies.json"), .{});
    defer parsed.deinit();
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    var current: ?ui.Scene = null;
    defer if (current) |*scene| scene.deinit();
    var short_panel_height: f32 = 0;
    var short_following_y: f32 = 0;
    for (parsed.value) |fixture| {
        const changes = try tree.applyChanges(fixture.patch);
        try std.testing.expectEqual(fixture.layout, changes.layout);
        try std.testing.expectEqual(fixture.paint, changes.paint);
        if (changes.layout or current == null) {
            if (current) |*scene| scene.deinit();
            current = null;
            current = try ui.Scene.fromTreeWithText(&tree, 500, 700, .{ .measure_fn = ui.text.fixedMeasurer(0.5) });
        } else {
            _ = try current.?.updateInputs(&tree, a, null);
        }
        var cold = try ui.Scene.initWithText(a, fixture.cold, 500, 700, .{ .measure_fn = ui.text.fixedMeasurer(0.5) });
        defer cold.deinit();
        try std.testing.expectEqual(cold.items.items.len, current.?.items.items.len);
        for (cold.items.items) |item| {
            const actual = current.?.find(item.node.id) orelse return error.MissingComputedCssNode;
            if (!ui.frame_inputs.equal(item.node.style, actual.node.style)) {
                inline for (@typeInfo(ui.Style).@"struct".field_names) |name| if (!ui.frame_inputs.equal(@field(item.node.style, name), @field(actual.node.style, name))) {
                    std.debug.print("CSS parity {s} node {d} field {s}: cold {any}, retained {any}\n", .{ fixture.name, item.node.id, name, @field(item.node.style, name), @field(actual.node.style, name) });
                };
                return error.ComputedCssStyleMismatch;
            }
            try std.testing.expectEqual(item.bounds, actual.bounds);
            try std.testing.expectEqual(item.parent_id, actual.parent_id);
        }
        // The panel is followed by two siblings; a text-only mutation must
        // expand its auto height and move the siblings, then restore both.
        const children = current.?.root.children[0].children;
        if (std.mem.eql(u8, fixture.name, "initial")) {
            short_panel_height = current.?.find(children[2].id).?.bounds.height;
            short_following_y = current.?.find(children[3].id).?.bounds.y;
        } else if (std.mem.startsWith(u8, fixture.name, "text changes")) {
            try std.testing.expect(current.?.find(children[2].id).?.bounds.height > short_panel_height);
            try std.testing.expect(current.?.find(children[3].id).?.bounds.y > short_following_y);
        } else if (std.mem.startsWith(u8, fixture.name, "text shrink")) {
            try std.testing.expectEqual(short_panel_height, current.?.find(children[2].id).?.bounds.height);
            try std.testing.expectEqual(short_following_y, current.?.find(children[3].id).?.bounds.y);
        }
    }
}

test "a leaf paint or hover update visits one identity in a thousand node scene" {
    const count = 1000;
    const Flat = struct { id: u32, type: []const u8 = "div", style: ui.Style = .{}, children: []const u32 = &.{} };
    const nodes = try a.alloc(Flat, count + 1);
    defer a.free(nodes);
    const ids = try a.alloc(u32, count);
    defer a.free(ids);
    for (nodes[1..], ids, 0..) |*node, *id, i| {
        id.* = @intCast(i + 2);
        node.* = .{ .id = id.*, .style = .{ .width = 10, .height = 10 } };
    }
    nodes[0] = .{ .id = 1, .type = "root", .children = ids };
    const json = try std.json.Stringify.valueAlloc(a, .{ .root = @as(u32, 1), .nodes = nodes }, .{});
    defer a.free(json);
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(json);
    var scene = try ui.Scene.fromTree(&tree, 500, 700);
    defer scene.deinit();
    const root_entry = tree.nodes.getPtr(1).?;
    const identity = scene.find(1001).?.node;
    const items = scene.items.items.ptr;
    const root_children = scene.root.children.ptr;
    const bounds = scene.find(1001).?.bounds;
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1001,"paint":{"style":{"backgroundColor":"red"}}}]}
    );
    const paint = try scene.updateInputs(&tree, a, null);
    try std.testing.expect(paint.paint);
    try std.testing.expectEqual(@as(usize, 1), paint.work.evaluated);
    try std.testing.expectEqual(@as(usize, 1), paint.work.paint);
    try std.testing.expectEqual(@as(usize, 0), paint.work.interaction);
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1001,"interaction":{"hovered":true,"style":{"cursor":"pointer"}}}]}
    );
    const hover = try scene.updateInputs(&tree, a, null);
    try std.testing.expect(!hover.paint);
    try std.testing.expectEqual(@as(usize, 1), hover.work.evaluated);
    try std.testing.expectEqual(@as(usize, 0), hover.work.paint);
    try std.testing.expectEqual(@as(usize, 1), hover.work.interaction);
    try std.testing.expectEqual(identity, scene.find(1001).?.node);
    try std.testing.expectEqual(items, scene.items.items.ptr);
    try std.testing.expectEqual(root_children, scene.root.children.ptr);
    try std.testing.expectEqual(bounds, scene.find(1001).?.bounds);
    try std.testing.expectEqual(root_entry, tree.nodes.getPtr(1).?);
    var timeline = ui.transitions.Timeline.init(a);
    defer timeline.deinit();
    var observer = TestRetarget{ .timeline = &timeline };
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1001,"paint":{"style":{"backgroundColor":"blue"}},"motion":{"transition":"background-color 1s linear"}}]}
    );
    _ = try scene.updateInputs(&tree, a, .{ .context = &observer, .style = TestRetarget.notify });
    try timeline.apply(&scene, 0.5);
    try std.testing.expectEqual(@as(usize, 1), scene.retained.last_work.evaluated);
    try std.testing.expectEqual(bounds, scene.find(1001).?.bounds);
    try timeline.apply(&scene, 0.5);
    try std.testing.expect(!timeline.paint_changed);
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1001,"paint":{}}]}
    );
    observer.now = 0.5;
    _ = try scene.updateInputs(&tree, a, .{ .context = &observer, .style = TestRetarget.notify });
    try std.testing.expect(!timeline.active());
    try std.testing.expectEqualStrings("", scene.find(1001).?.node.style.backgroundColor);
}

test "inheritance read edges update even when the effective value is unchanged" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"color":"red","cursor":"pointer"},"children":[2,4]},{"id":2,"type":"div","style":{"textDecoration":"underline","textDecorationLine":"underline","textEmphasisStyle":"circle","textDecorationColor":"red","textEmphasisColor":"red"},"children":[3]},{"id":3,"type":"text","text":"inherited"},{"id":4,"type":"div","style":{"color":"green","cursor":"crosshair","textDecoration":"underline","textDecorationLine":"underline","textEmphasisStyle":"circle","textDecorationColor":"green","textEmphasisColor":"green"},"children":[5]},{"id":5,"type":"text","text":"isolated"}]}
    );
    var scene = try ui.Scene.fromTree(&tree, 300, 200);
    defer scene.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"paint":{"style":{"color":"red","textDecorationColor":"red","textEmphasisColor":"red"}}}]}
    );
    const ownership = try scene.updateInputs(&tree, a, null);
    try std.testing.expect(!ownership.paint);
    try std.testing.expectEqual(@as(usize, 1), ownership.work.evaluated);
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"blue"}}}]}
    );
    const isolated = try scene.updateInputs(&tree, a, null);
    try std.testing.expectEqual(@as(usize, 1), isolated.work.evaluated);
    try std.testing.expectEqualStrings("red", scene.find(3).?.node.style.color);
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":2,"paint":{}}]}
    );
    const restore = try scene.updateInputs(&tree, a, null);
    try std.testing.expectEqual(@as(usize, 2), restore.work.evaluated);
    try std.testing.expectEqualStrings("blue", scene.find(3).?.node.style.color);
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"purple"}},"interaction":{"style":{"cursor":"help"}}},{"id":2,"paint":{"style":{"backgroundColor":"yellow"}}}]}
    );
    const propagate = try scene.updateInputs(&tree, a, null);
    try std.testing.expectEqual(@as(usize, 3), propagate.work.evaluated);
    try std.testing.expectEqualStrings("purple", scene.find(3).?.node.style.color);
    try std.testing.expectEqualStrings("help", scene.find(3).?.node.style.cursor);
    try std.testing.expectEqualStrings("green", scene.find(5).?.node.style.color);
    try std.testing.expectEqualStrings("crosshair", scene.find(5).?.node.style.cursor);
}

const TestRetarget = struct {
    timeline: *ui.transitions.Timeline,
    now: f64 = 0,
    fn notify(context: *anyopaque, id: u32, before: ui.Style, after: ui.Style) anyerror!void {
        const self: *TestRetarget = @ptrCast(@alignCast(context));
        try self.timeline.retargetPaint(id, before, after, self.now);
    }
};
test "retained paint transitions sample active identities and propagate inherited color" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(initial);
    var scene = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
    defer scene.deinit();
    var timeline = ui.transitions.Timeline.init(a);
    defer timeline.deinit();
    var observer = TestRetarget{ .timeline = &timeline };
    const before_measurements = measurements;
    const before_bounds = scene.find(2).?.bounds;
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"blue"}},"motion":{"transition":"color 1s linear"}}]}
    );
    _ = try scene.updateInputs(&tree, a, .{ .context = &observer, .style = TestRetarget.notify });
    try std.testing.expect(timeline.active());
    try std.testing.expect(!timeline.needsLayout());
    for (0..100) |i| {
        try timeline.apply(&scene, @as(f64, @floatFromInt(i)) / 100);
        try std.testing.expectEqual(@as(usize, 2), scene.retained.last_work.evaluated);
        try std.testing.expectEqualStrings(scene.find(1).?.node.style.color, scene.find(2).?.node.style.color);
        try std.testing.expectEqualStrings(scene.find(1).?.node.style.color, scene.find(2).?.node.style.borderColor);
        try std.testing.expectEqual(before_bounds, scene.find(2).?.bounds);
    }
    try timeline.apply(&scene, 2);
    try std.testing.expect(!timeline.active());
    try std.testing.expectEqualStrings("blue", scene.find(2).?.node.style.color);
    try std.testing.expectEqual(before_measurements, measurements);
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"red"}}}]}
    );
    observer.now = 3;
    _ = try scene.updateInputs(&tree, a, .{ .context = &observer, .style = TestRetarget.notify });
    try timeline.apply(&scene, 3.5);
    try std.testing.expect(timeline.active());
    _ = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"motion":{"transition":"none"}}]}
    );
    observer.now = 3.5;
    _ = try scene.updateInputs(&tree, a, .{ .context = &observer, .style = TestRetarget.notify });
    try std.testing.expect(!timeline.active());
    try std.testing.expectEqualStrings("red", scene.find(2).?.node.style.color);
}

test "retained phase updates remain retryable after every allocation failure" {
    var success = false;
    for (0..100) |fail_at| {
        var tree = ui.Tree.init(a);
        defer tree.deinit();
        _ = try tree.applyChanges(initial);
        var failing = std.testing.FailingAllocator.init(a, .{});
        var scene = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
        defer scene.deinit();
        // The retained phase pools and reverse edges use this allocator; the
        // existing layout arena remains independently owned.
        scene.retained.allocator = failing.allocator();
        _ = try tree.applyChanges(
            \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"blue","boxShadow":"0 0 1px currentColor"}}},{"id":2,"interaction":{"style":{"cursor":"pointer"}}}]}
        );
        const before = scene.find(1).?.node.style;
        failing.fail_index = fail_at;
        _ = scene.updateInputs(&tree, failing.allocator(), null) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(ui.frame_inputs.equal(before, scene.find(1).?.node.style));
            try std.testing.expectEqualStrings("auto", scene.find(2).?.node.style.cursor);
            failing.fail_index = std.math.maxInt(usize);
            _ = try scene.updateInputs(&tree, a, null);
            try std.testing.expectEqualStrings("blue", scene.find(2).?.node.style.color);
            try std.testing.expectEqualStrings("pointer", scene.find(2).?.node.style.cursor);
            continue;
        };
        success = true;
        break;
    }
    try std.testing.expect(success);
}
