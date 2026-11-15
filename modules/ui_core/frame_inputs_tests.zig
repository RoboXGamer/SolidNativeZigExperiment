const std = @import("std");
const ui = @import("root.zig");
const a = std.testing.allocator;
const initial =
    \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"width":300,"color":"red"},"children":[2]},{"id":2,"type":"text","text":"hello world","style":{"fontSize":16,"fontWeightCss":"bolder","borderColor":"currentColor"}}]}
;
var measurements: usize = 0;
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
    try scene.syncInteraction(&tree);
    try std.testing.expect(retained_node == scene.find(2).?.node);
    try std.testing.expectEqualStrings("pointer", scene.find(2).?.node.style.cursor);
    try std.testing.expect(scene.find(2).?.node.hovered);
    const paint = try tree.applyChanges(
        \\{"root":1,"updates":[{"id":1,"paint":{"style":{"color":"blue","opacityCss":"0.6","outlineWidth":2,"outlineStyle":"solid"}}}]}
    );
    try std.testing.expect(paint.paint and !paint.layout);
    var next = try scene.refreshPaint(&tree);
    try std.testing.expect(ui.frame_inputs.equal(@import("style.zig").select(@import("style.zig").LayoutStyle, scene.find(2).?.node.style), @import("style.zig").select(@import("style.zig").LayoutStyle, next.find(2).?.node.style)));
    scene.deinit();
    scene = next;
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
    next = try ui.Scene.fromTreeWithText(&tree, 300, 200, .{ .measure_fn = measure });
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
    var next = try old.refreshPaint(&tree);
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
test "paint refreshes own data and scroll offsets do not accumulate" {
    var tree = ui.Tree.init(a);
    defer tree.deinit();
    _ = try tree.applyChanges(
        \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"width":200,"height":60,"overflow":"scroll"},"children":[2]},{"id":2,"type":"column","style":{"width":100,"height":300}}]}
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
        const next = try scene.refreshPaint(&tree);
        scene.deinit();
        scene = next;
        try std.testing.expectEqual(y, scene.find(2).?.bounds.y);
    }
}
