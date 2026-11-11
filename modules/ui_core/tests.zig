const std = @import("std");
const root = @import("root.zig");
const Scene = root.Scene;

test "layout and hit testing use node identity" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"button","clickable":true,"children":[{"id":3,"type":"text","text":"Click"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(?u32, 2), scene.hitTest(5, 5));
    try std.testing.expectEqual(@as(?u32, null), scene.hitTest(301, 5));
}

test "per-side padding and border affect layout" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"paddingTop":5,"paddingLeft":2,"margin":4},"children":[{"id":3,"type":"text","text":"hi"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expect(b.x > 0);
    try std.testing.expect(b.width <= 300);
}

test "min/max and aspect ratio constraints" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"minWidth":50,"maxWidth":100,"aspectRatio":2},"children":[]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expect(b.width >= 50 and b.width <= 100);
    try std.testing.expect(b.height > 0);
}

test "block layout sibling margin collapsing" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"height":10,"marginBottom":20}},{"id":3,"type":"column","style":{"height":10,"marginTop":30}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b2 = scene.items.items[1].bounds;
    const b3 = scene.items.items[2].bounds;
    try std.testing.expect(b3.y >= b2.y + b2.height + 20);
}

test "empty block margins collapse through" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"height":10,"marginBottom":20}},{"id":3,"type":"column","style":{"marginTop":30,"marginBottom":40}},{"id":4,"type":"column","style":{"height":10,"marginTop":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const b2 = scene.items.items[1].bounds;
    const b3 = scene.items.items[2].bounds;
    const b4 = scene.items.items[3].bounds;
    // Empty block adds no height and all four margins collapse into one gap.
    try std.testing.expectEqual(@as(f32, 0), b3.height);
    try std.testing.expectApproxEqAbs(b2.y + b2.height + 40, b4.y, 0.01);
}

test "row container keeps sibling text on one line" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"column"},"children":[{"id":2,"type":"label","style":{"display":"flex","flexDirection":"row"},"children":[{"id":3,"type":"text","text":"Loading states: "},{"id":4,"type":"text","text":"no"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const label = scene.items.items[1].bounds;
    const first = scene.items.items[2].bounds;
    const second = scene.items.items[3].bounds;
    // Regression: text siblings must stay inline and the container must be as
    // tall as one line, not the sum of its children (which produced overlap).
    try std.testing.expectEqual(first.y, second.y);
    try std.testing.expect(second.x >= first.x + first.width);
    try std.testing.expectApproxEqAbs(first.height, label.height, 0.01);
}

test "text intrinsic width follows the injected metrics" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"abcd","style":{"flexBasis":-2}}]}
    ;
    // Fallback estimate: 4 glyphs * 0.5em * 20px = 40px.
    var estimated = try Scene.init(std.testing.allocator, json, 300, 100);
    defer estimated.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 40), estimated.items.items[1].bounds.width, 1);

    // A real measurer reporting 1em per glyph doubles the intrinsic width.
    var measured = try Scene.initWithText(std.testing.allocator, json, 300, 100, .{ .measure_fn = root.text.fixedMeasurer(1.0) });
    defer measured.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 80), measured.items.items[1].bounds.width, 1);
}

test "text line height comes from the measurer" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"text","text":"hi"}]}
    ;
    var estimated = try Scene.init(std.testing.allocator, json, 300, 100);
    defer estimated.deinit();
    var measured = try Scene.initWithText(std.testing.allocator, json, 300, 100, .{ .measure_fn = root.text.fixedMeasurer(0.5) });
    defer measured.deinit();
    const h_est = estimated.items.items[1].bounds.height;
    const h_meas = measured.items.items[1].bounds.height;
    // Estimate uses 1.2em leading; the test measurer reports 1.0em.
    try std.testing.expectApproxEqAbs(@as(f32, 24), h_est, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 20), h_meas, 0.5);
}

test "margin auto resolves through the box model" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column"}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const child = scene.items.items[1].node;
    try std.testing.expectEqual(@as(f32, 0), child.margin().left);
    try std.testing.expectEqual(@as(f32, 0), child.margin().right);
}

test "nested overflow parent tracking" {
    const json =
        \\{"id":1,"type":"root","children":[{"id":2,"type":"column","style":{"overflow":"hidden"},"children":[{"id":3,"type":"text","text":"hi"}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const child = scene.items.items[2];
    try std.testing.expectEqual(@as(?u32, 2), child.parent_id);
}

test "flex auto margins center an item on the main axis" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":100,"height":20,"marginLeft":-1,"marginRight":-1}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    // (300 - 100) / 2 == 100
    try std.testing.expectApproxEqAbs(@as(f32, 100), b.x, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b.width, 0.01);
}

test "flex auto margin on one side pushes the item to the end" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":50,"height":20,"marginLeft":-1}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 250), b.x, 1);
}

test "flex-basis auto uses the definite main size" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":80,"height":20}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 80), b.width, 0.01);
}

test "flex-basis content uses intrinsic max-content width" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"hello","style":{"flexBasis":-2}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    // 5 glyphs * 20px * 0.5 = 50px
    try std.testing.expectApproxEqAbs(@as(f32, 50), b.width, 1);
}

test "flex cross auto margins center an item on the cross axis" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":50,"height":20,"marginTop":-1,"marginBottom":-1}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    // Single line stretches to 100px, item is 20px tall -> centered at 40px.
    try std.testing.expectApproxEqAbs(@as(f32, 40), b.y, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 20), b.height, 0.01);
}

test "explicit flex-basis overrides the width property" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":50,"height":20,"flexBasis":120}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 120), b.width, 0.01);
}

test "flex-basis auto falls back to content size" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"hello"}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 50), b.width, 1);
}

test "flex shrink stops at min-content width" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"hello world","style":{"flexShrink":1}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 20, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    // Longest word "hello" / "world" -> 5 * 20 * 0.5 = 50px minimum.
    try std.testing.expect(b.width >= 49);
}
