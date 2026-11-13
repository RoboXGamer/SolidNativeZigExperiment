const std = @import("std");
const root = @import("root.zig");
const Scene = root.Scene;

// These regression fixtures were written under the application testing pause.
test "typed length arithmetic and missing contexts" {
    const sizing = root.sizing;
    const ctx: sizing.Context = .{ .percentage = 200, .font_size = 20, .root_font_size = 16, .viewport_width = 1000, .viewport_height = 500, .small_viewport_height = 400, .large_viewport_height = 600, .dynamic_viewport_height = 450, .container_inline = 300 };
    try std.testing.expectEqual(@as(f32, 96), (try sizing.resolve("1in", ctx)).length);
    try std.testing.expectEqual(@as(f32, 52), (try sizing.resolve("calc(10% + 2em - 8px)", ctx)).length);
    try std.testing.expectEqual(@as(f32, 100), (try sizing.resolve("clamp(20px, 10vw, 120px)", ctx)).length);
    try std.testing.expectEqual(@as(f32, 50), (try sizing.resolve("10vmin", ctx)).length);
    try std.testing.expectEqual(@as(f32, 40), (try sizing.resolve("10svh", ctx)).length);
    try std.testing.expectEqual(@as(f32, 60), (try sizing.resolve("10lvh", ctx)).length);
    try std.testing.expectEqual(@as(f32, 45), (try sizing.resolve("10dvh", ctx)).length);
    try std.testing.expectEqual(@as(f32, 30), (try sizing.resolve("10cqi", ctx)).length);
    switch (try sizing.resolve("2ch", ctx)) {
        .unresolved => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectError(error.UnsupportedUnit, sizing.resolve("1bogus", ctx));
    try std.testing.expectError(error.IncompatibleDimensions, sizing.resolve("calc(1px + 2)", ctx));
    try std.testing.expectError(error.InvalidLength, sizing.resolve("NaN", ctx));
    try std.testing.expectError(error.InvalidLength, sizing.resolve("Infinity", ctx));
}

test "percentage sizes and padding use containing inline size" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"boxSizing":"border-box","widthCss":"50%","heightCss":"10px","paddingLeftCss":"10%","marginLeftCss":"5%"}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    const child = scene.find(2).?;
    try std.testing.expectEqual(@as(f32, 100), child.bounds.width);
    try std.testing.expectEqual(@as(f32, 10), child.bounds.x);
    try std.testing.expectEqual(@as(f32, 20), child.node.padding().left);
}

test "explicit zero and none remain distinct" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":0,"height":0,"maxWidth":0}},{"id":3,"type":"column","style":{"maxWidthCss":"none","height":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 0), scene.find(2).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 0), scene.find(2).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 200), scene.find(3).?.bounds.width);
}

test "explicit zero on root is definite" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":0,"height":0}}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 0), scene.find(1).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 0), scene.find(1).?.bounds.height);
}

test "block horizontal auto margins distribute space" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":100,"height":10,"marginLeftAuto":true,"marginRightAuto":true}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 100), scene.find(2).?.bounds.x);
    try std.testing.expectEqual(@as(f32, 0), scene.find(2).?.marginBox().x);
    try std.testing.expectEqual(@as(f32, 300), scene.find(2).?.marginBox().width);
}

test "over-wide block child is not clamped to parent width" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":400,"height":20}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 400), scene.find(2).?.bounds.width);
}

test "flex explicit zero minimum permits shrinking" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"abcdefghij","style":{"minWidth":0,"flexBasis":100}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 20, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 20), scene.find(2).?.bounds.width);
}

test "aspect ratio transfers one definite axis" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":100,"aspectRatio":2}},{"id":3,"type":"column","style":{"height":30,"aspectRatio":2}},{"id":4,"type":"column","style":{"width":100,"height":40,"aspectRatio":2}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 50), scene.find(2).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 60), scene.find(3).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 40), scene.find(4).?.bounds.height);
}

test "content box ratio and conflicting constraints" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":100,"padding":10,"borderWidth":2,"boxSizing":"content-box","aspectRatio":2,"minHeight":60,"maxHeight":30}},{"id":3,"type":"column","style":{"heightCss":"50%","width":20,"aspectRatio":2}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 124), scene.find(2).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 84), scene.find(2).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 100), scene.find(3).?.bounds.height);
}

test "indefinite percentage height remains auto for ratio" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"block"},"children":[{"id":3,"type":"column","style":{"width":100,"heightCss":"50%","aspectRatio":2}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 50), scene.find(3).?.bounds.height);
}

test "grid and flex constraints use minimum after maximum" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"grid","height":100,"columns":[100]},"children":[{"id":3,"type":"column","style":{"width":75,"height":75,"minWidth":100,"maxWidth":50,"minHeight":100,"maxHeight":50}}]},{"id":4,"type":"column","style":{"display":"flex","height":100},"children":[{"id":5,"type":"column","style":{"width":75,"height":75,"minWidth":100,"maxWidth":50,"minHeight":100,"maxHeight":50}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 300);
    defer scene.deinit();
    for ([_]u32{ 3, 5 }) |id| {
        try std.testing.expectEqual(@as(f32, 100), scene.find(id).?.bounds.width);
        try std.testing.expectEqual(@as(f32, 100), scene.find(id).?.bounds.height);
    }
}

test "intrinsic width keywords use measured text" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"text","text":"aa bbbb","style":{"widthCss":"min-content"}},{"id":3,"type":"text","text":"aa bbbb","style":{"widthCss":"max-content"}},{"id":4,"type":"text","text":"aa bbbb","style":{"widthCss":"fit-content(50px)"}}]}
    ;
    var scene = try Scene.initWithText(std.testing.allocator, json, 300, 100, .{ .measure_fn = root.text.fixedMeasurer(0.5) });
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 40), scene.find(2).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 70), scene.find(3).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 50), scene.find(4).?.bounds.width);
    const leaf = scene.find(3).?.node;
    try std.testing.expectEqual(@as(f32, 40), scene.intrinsicWidthFor(leaf, .min_content));
    try std.testing.expectEqual(@as(f32, 70), scene.intrinsicWidthFor(leaf, .max_content));
    try std.testing.expectEqual(@as(f32, 50), scene.intrinsicWidthFor(leaf, .{ .definite = 50 }));
}

test "tree owns changed css length strings" {
    var tree = root.Tree.init(std.testing.allocator);
    defer tree.deinit();
    const first =
        \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"display":"block"},"children":[2]},{"id":2,"type":"column","style":{"widthCss":"50%","height":10}}]}
    ;
    const changed =
        \\{"root":1,"nodes":[{"id":2,"type":"column","style":{"widthCss":"calc(25% + 5px)","height":10}}]}
    ;
    try std.testing.expect(try tree.apply(first));
    try std.testing.expect(try tree.apply(changed));
    {
        var scene = try Scene.fromTree(&tree, 200, 100);
        defer scene.deinit();
        try std.testing.expectEqual(@as(f32, 55), scene.find(2).?.bounds.width);
    }
    const removed =
        \\{"root":1,"nodes":[{"id":1,"type":"root","style":{"display":"block"},"children":[]}],"removed":[2]}
    ;
    try std.testing.expect(try tree.apply(removed));
    try std.testing.expect(try tree.apply(first));
    try std.testing.expect(try tree.apply(changed));
    try std.testing.expect(try tree.apply(removed));
    var empty = try Scene.fromTree(&tree, 200, 100);
    defer empty.deinit();
    try std.testing.expect(empty.find(2) == null);
}
test "zero sides override shorthand and control defaults" {
    const ordinary = root.Node{ .id = 1, .type = "column", .style = .{ .padding = 20, .paddingLeft = 0, .borderWidth = 4, .borderLeftWidth = 0, .margin = 20, .marginLeft = 0 } };
    try std.testing.expectEqual(@as(f32, 0), ordinary.padding().left);
    try std.testing.expectEqual(@as(f32, 20), ordinary.padding().right);
    try std.testing.expectEqual(@as(f32, 0), ordinary.border().left);
    try std.testing.expectEqual(@as(f32, 4), ordinary.border().right);
    try std.testing.expectEqual(@as(f32, 0), ordinary.margin().left);
    const button = root.Node{ .id = 2, .type = "button" };
    const reset = root.Node{ .id = 3, .type = "button", .style = .{ .padding = 0 } };
    try std.testing.expectEqual(@as(f32, 10), button.padding().left);
    try std.testing.expectEqual(@as(f32, 0), reset.padding().left);
}

test "negative one margin differs from auto" {
    const fixed = root.Node{ .id = 1, .type = "column", .style = .{ .marginLeft = -1 } };
    const automatic = root.Node{ .id = 2, .type = "column", .style = .{ .marginLeftAuto = true } };
    try std.testing.expectEqual(@as(f32, -1), fixed.margin().left);
    try std.testing.expectEqual(@as(f32, 0), automatic.margin().left);
}

test "content and border box dimensions include frame once" {
    const content = root.Node{ .id = 1, .type = "column", .style = .{ .padding = 10, .borderWidth = 2, .boxSizing = "content-box" } };
    const border = root.Node{ .id = 2, .type = "column", .style = .{ .padding = 10, .borderWidth = 2, .boxSizing = "border-box" } };
    try std.testing.expectEqual(@as(f32, 124), content.borderSize(100, 24));
    try std.testing.expectEqual(@as(f32, 64), content.borderSize(40, 24));
    try std.testing.expectEqual(@as(f32, 100), border.borderSize(100, 24));
    try std.testing.expectEqual(@as(f32, 40), border.borderSize(40, 24));
    try std.testing.expectEqual(@as(f32, 24), border.borderSize(0, 24));
}

test "layout applies box sizing to both axes" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":100,"height":40,"padding":10,"borderWidth":2,"boxSizing":"content-box"}},{"id":3,"type":"column","style":{"width":100,"height":40,"padding":10,"borderWidth":2,"boxSizing":"border-box"}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    const content = scene.find(2).?.bounds;
    const border = scene.find(3).?.bounds;
    try std.testing.expectEqual(@as(f32, 124), content.width);
    try std.testing.expectEqual(@as(f32, 64), content.height);
    try std.testing.expectEqual(@as(f32, 100), border.width);
    try std.testing.expectEqual(@as(f32, 40), border.height);
}

test "contents and none generate only descendant boxes" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"none"},"children":[{"id":3,"type":"button","clickable":true}]},{"id":4,"type":"column","style":{"display":"contents"},"children":[{"id":5,"type":"column","style":{"height":10}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();
    try std.testing.expect(scene.find(2) == null);
    try std.testing.expect(scene.find(3) == null);
    try std.testing.expect(scene.find(4) == null);
    try std.testing.expectEqual(@as(f32, 10), scene.find(5).?.bounds.height);
    try std.testing.expectEqual(@as(?u32, null), scene.hitTest(1, 1));
}

test "unsupported formatting is rejected instead of flex fallback" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"table"}}]}
    ;
    try std.testing.expectError(error.UnsupportedDisplay, Scene.init(std.testing.allocator, json, 100, 100));
}
test "block sibling advances by constrained height" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"height":10,"minHeight":50}},{"id":3,"type":"column","style":{"height":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 50), scene.find(2).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 50), scene.find(3).?.bounds.y);
}

test "nested auto block measures child ratio before sibling placement" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"block","width":100},"children":[{"id":3,"type":"column","style":{"aspectRatio":2}}]},{"id":4,"type":"column","style":{"height":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 50), scene.find(2).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 50), scene.find(3).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 50), scene.find(4).?.bounds.y);
}

test "block natural height ignores flex direction" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"block","flexDirection":"row"},"children":[{"id":3,"type":"column","style":{"height":10}},{"id":4,"type":"column","style":{"height":10}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 20), scene.find(2).?.bounds.height);
    try std.testing.expectEqual(@as(f32, 10), scene.find(4).?.bounds.y);
}

test "nested block margin is an outer offset" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"block","width":100,"marginLeft":10},"children":[{"id":3,"type":"column","style":{"width":100,"height":10}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 10), scene.find(2).?.bounds.x);
    try std.testing.expectEqual(@as(f32, 10), scene.find(3).?.bounds.x);
    try std.testing.expectEqual(@as(f32, 100), scene.find(3).?.bounds.width);
}

test "minimum wins conflicting maximum" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"width":75,"height":75,"minWidth":100,"maxWidth":50,"minHeight":100,"maxHeight":50}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 100), scene.find(2).?.bounds.width);
    try std.testing.expectEqual(@as(f32, 100), scene.find(2).?.bounds.height);
}

test "grid tracks do not override block display" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","columns":[30,30]},"children":[{"id":2,"type":"column","style":{"height":10}},{"id":3,"type":"column","style":{"height":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 0), scene.find(3).?.bounds.x);
    try std.testing.expectEqual(@as(f32, 10), scene.find(3).?.bounds.y);
}

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
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"abcd","style":{"flexBasisContent":true}}]}
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
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":100,"height":20,"marginLeftAuto":true,"marginRightAuto":true}}]}
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
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":50,"height":20,"marginLeftAuto":true}}]}
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
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"text","text":"hello","style":{"flexBasisContent":true}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    const b = scene.items.items[1].bounds;
    // 5 glyphs * 20px * 0.5 = 50px
    try std.testing.expectApproxEqAbs(@as(f32, 50), b.width, 1);
}

test "flex cross auto margins center an item on the cross axis" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row"},"children":[{"id":2,"type":"column","style":{"width":50,"height":20,"marginTopAuto":true,"marginBottomAuto":true}}]}
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

test "C-PARTIAL-GROW: partial flex factors sum < 1 (FLEX-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":100},"children":[{"id":2,"type":"column","style":{"flexGrow":0.25,"flexBasis":0,"minWidth":0}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 50);
    defer scene.deinit();
    const b = scene.find(2).?.bounds;
    // 100px row, basis 0, grow 0.25 -> 25px
    try std.testing.expectApproxEqAbs(@as(f32, 25), b.width, 0.01);
}

test "partial flex shrink factor sum < 1 (FLEX-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":100},"children":[{"id":2,"type":"column","style":{"flexBasis":140,"flexShrink":0.5}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 50);
    defer scene.deinit();
    const b = scene.find(2).?.bounds;
    // 100px container, 140px item, free space -40. shrink factor 0.5 consumes -20 -> 120px
    try std.testing.expectApproxEqAbs(@as(f32, 120), b.width, 0.01);
}

test "C-BASIS-MIN: raw flex bases separate from hypothetical sizes (FLEX-02)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":200},"children":[{"id":2,"type":"column","style":{"flexGrow":1,"flexBasis":0,"minWidth":80}},{"id":3,"type":"column","style":{"flexGrow":1,"flexBasis":0,"minWidth":0}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 50);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;
    // 200px row, two grow-1 basis-0 items. Free space = 200. Each gets 100.
    // Minima: item 2 has 80 (100 >= 80, no violation). item 3 has 0.
    // Result: 100 / 100, NOT 140 / 60 from pre-clamping!
    try std.testing.expectApproxEqAbs(@as(f32, 100), b2.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b3.width, 0.01);
}

test "flex iterative loop freezing violating items (FLEX-02)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":200},"children":[{"id":2,"type":"column","style":{"flexGrow":1,"flexBasis":0,"minWidth":130}},{"id":3,"type":"column","style":{"flexGrow":1,"flexBasis":0,"minWidth":0}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 50);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;
    // Iteration 1: each gets 100. Item 2 has min 130 -> violation +30.
    // Item 2 freezes at 130.
    // Iteration 2: remaining free space = 200 - 130 = 70. Item 3 gets 70.
    try std.testing.expectApproxEqAbs(@as(f32, 130), b2.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 70), b3.width, 0.01);
}

test "C-NOWRAP-CROSS: single-line definite cross size fills line (FLEX-04)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","flexWrap":"nowrap","alignContent":"flex-start","alignItems":"stretch","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"width":50}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    // Single line with definite 100px cross size fills the line cross size
    // independently of alignContent (alignContent flex-start does not prevent stretch).
    try std.testing.expectApproxEqAbs(@as(f32, 100), b2.height, 0.01);
}

test "wrap-reverse single line reverses cross position (FLEX-04)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","flexWrap":"wrap-reverse","alignItems":"flex-start","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"width":50,"height":30}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    // Line cross size is 30. In wrap-reverse with 100px cross height:
    // line is placed at 100 - 30 = 70.
    try std.testing.expectApproxEqAbs(@as(f32, 70), b2.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 30), b2.height, 0.01);
}

test "cross size remeasurement after main flexing (FLEX-05)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":200},"children":[{"id":2,"type":"column","style":{"flexGrow":1,"flexBasis":50,"aspectRatio":2}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 200);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    // Item flexes from basis 50 to final width 200.
    // Cross height is remeasured using the flexed main size 200 / 2 = 100!
    try std.testing.expectApproxEqAbs(@as(f32, 200), b2.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b2.height, 0.01);
}

test "visual order preserves document focus sequence (FLEX-06)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":200},"children":[{"id":2,"type":"button","clickable":true,"style":{"order":2,"width":50,"height":20,"boxSizing":"border-box"}},{"id":3,"type":"button","clickable":true,"style":{"order":1,"width":50,"height":20,"boxSizing":"border-box"}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 50);
    defer scene.deinit();
    // Visual order: item 3 has order 1 -> placed at x = 0.
    // Item 2 has order 2 -> placed at x = 50.
    try std.testing.expectApproxEqAbs(@as(f32, 50), scene.find(2).?.bounds.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), scene.find(3).?.bounds.x, 0.01);
    // Document order in scene.items: item 2 MUST appear before item 3!
    try std.testing.expectEqual(@as(u32, 2), scene.items.items[1].node.id);
    try std.testing.expectEqual(@as(u32, 3), scene.items.items[2].node.id);
}

test "typed flex-basis keywords and percentages (FLEX-07)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":200},"children":[{"id":2,"type":"column","style":{"flexBasisCss":"50%"}},{"id":3,"type":"text","text":"hi","style":{"flexBasisCss":"max-content"}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 50);
    defer scene.deinit();
    // 50% of 200px = 100px
    try std.testing.expectApproxEqAbs(@as(f32, 100), scene.find(2).?.bounds.width, 0.01);
    // max-content for text "hi": 2 * 20 * 0.5 = 20px
    try std.testing.expectApproxEqAbs(@as(f32, 20), scene.find(3).?.bounds.width, 1);
}

test "flex rowGap and columnGap support (FLEX-07)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","flexWrap":"wrap","alignContent":"flex-start","width":100,"rowGap":15,"columnGap":10},"children":[{"id":2,"type":"column","style":{"width":50,"height":20}},{"id":3,"type":"column","style":{"width":40,"height":20}},{"id":4,"type":"column","style":{"width":50,"height":20}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;
    const b4 = scene.find(4).?.bounds;
    // Row 1: item 2 at x=0, columnGap 10, item 3 at x=60. (50 + 10 + 40 = 100 fits)
    try std.testing.expectApproxEqAbs(@as(f32, 0), b2.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 60), b3.x, 0.01);
    // Row 2: item 4 wraps. rowGap 15 -> y = 20 + 15 = 35.
    try std.testing.expectApproxEqAbs(@as(f32, 35), b4.y, 0.01);
}

test "C-COLLAPSE-SET: multi-margin strut preserves positive and negative extrema (BLOCK-04)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flow-root","width":200},"children":[{"id":2,"type":"column","style":{"height":10,"marginBottom":20}},{"id":3,"type":"column","style":{"marginTop":-10,"marginBottom":15}},{"id":4,"type":"column","style":{"height":10,"marginTop":0}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    const b4 = scene.find(4).?.bounds;
    // b2 bottom is at 10. Gap between b2 and b4 is 10. b4 starts at 20!
    try std.testing.expectApproxEqAbs(@as(f32, 0), b2.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20), b4.y, 0.01);
}

test "C-CLIP-BFC: overflow:clip does not establish BFC while hidden does (BLOCK-06)" {
    const jsonClip =
        \\{"id":1,"type":"root","style":{"display":"block","overflow":"clip","width":200},"children":[{"id":2,"type":"column","style":{"height":20,"marginTop":15}}]}
    ;
    var sceneClip = try Scene.init(std.testing.allocator, jsonClip, 200, 100);
    defer sceneClip.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 0), sceneClip.find(2).?.bounds.y, 0.01);

    const jsonHidden =
        \\{"id":1,"type":"root","style":{"display":"block","overflow":"hidden","width":200},"children":[{"id":2,"type":"column","style":{"height":20,"marginTop":15}}]}
    ;
    var sceneHidden = try Scene.init(std.testing.allocator, jsonHidden, 200, 100);
    defer sceneHidden.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 15), sceneHidden.find(2).?.bounds.y, 0.01);
}

test "parent and child top and bottom margin collapsing (BLOCK-05)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block"},"children":[{"id":2,"type":"column","style":{"display":"block"},"children":[{"id":3,"type":"column","style":{"height":30,"marginTop":10,"marginBottom":25}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    const parent = scene.find(2).?.bounds;
    const child = scene.find(3).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 0), child.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 30), parent.height, 0.01);
}

test "baseline alignment with nested text child" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","alignItems":"baseline","width":200,"height":60},"children":[{"id":2,"type":"button","style":{"paddingTop":10,"height":40},"children":[{"id":3,"type":"text","text":"A"}]},{"id":4,"type":"text","text":"B"}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 60);
    defer scene.deinit();
    const btn = scene.find(2).?.bounds;
    const t = scene.find(4).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 10), t.y, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), btn.y, 0.01);
}

test "C-TEXT-LINES: multi-line wrap and line height synthesis (TEXT-01, TEXT-04)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":100},"children":[{"id":2,"type":"text","text":"one two three four five six seven","style":{"fontSize":16,"lineHeight":24}}]}
    ;
    // Default text measurer: 0.5 * font_size = 8px per char.
    // "one two three four five six seven" has 33 chars = 264px.
    // In width 100, words wrap into multiple lines!
    var scene = try Scene.init(std.testing.allocator, json, 100, 200);
    defer scene.deinit();
    const t = scene.find(2).?.bounds;
    // With lineHeight 24 and multiple lines, height should be a multiple of 24 and > 24
    try std.testing.expect(t.height >= 48);
    try std.testing.expectApproxEqAbs(@as(f32, 0), @mod(t.height, 24), 0.01);

    // Now test whiteSpace nowrap: keeps single line
    const jsonNowrap =
        \\{"id":1,"type":"root","style":{"display":"block","width":100},"children":[{"id":2,"type":"text","text":"one two three four five six seven","style":{"fontSize":16,"lineHeight":24,"whiteSpace":"nowrap"}}]}
    ;
    var sceneNowrap = try Scene.init(std.testing.allocator, jsonNowrap, 100, 200);
    defer sceneNowrap.deinit();
    const tNowrap = sceneNowrap.find(2).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 24), tNowrap.height, 0.01);
}

test "baseline synthesis: first-baseline and last-baseline alignment (TEXT-02)" {
    // Flex container with two items: item 2 has height 40, item 3 has height 60.
    const jsonFirst =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","alignItems":"first-baseline","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"height":40}},{"id":3,"type":"column","style":{"height":60}}]}
    ;
    var sceneFirst = try Scene.init(std.testing.allocator, jsonFirst, 200, 100);
    defer sceneFirst.deinit();
    const b2First = sceneFirst.find(2).?.bounds;
    const b3First = sceneFirst.find(3).?.bounds;
    // For boxes without text, baseline is synthesize from bottom.
    // max baseline is 60. Item 2 baseline is 40 -> shifted by 60 - 40 = 20.
    try std.testing.expectApproxEqAbs(@as(f32, 20), b2First.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b3First.y, 0.01);

    const jsonLast =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","alignItems":"last-baseline","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"height":40}},{"id":3,"type":"column","style":{"height":60}}]}
    ;
    var sceneLast = try Scene.init(std.testing.allocator, jsonLast, 200, 100);
    defer sceneLast.deinit();
    const b2Last = sceneLast.find(2).?.bounds;
    const b3Last = sceneLast.find(3).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 20), b2Last.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b3Last.y, 0.01);
}

test "IFC: inline formatting context with inline-flex boxes (TEXT-02)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":150},"children":[{"id":2,"type":"column","style":{"display":"inline-flex","width":60,"height":20}},{"id":3,"type":"column","style":{"display":"inline-flex","width":60,"height":20}},{"id":4,"type":"column","style":{"display":"inline-flex","width":60,"height":20}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 150, 100);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;
    const b4 = scene.find(4).?.bounds;
    // Item 2 and 3 fit on Line 1 (60 + 60 = 120 <= 150)
    try std.testing.expectApproxEqAbs(@as(f32, 0), b2.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b2.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 60), b3.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b3.y, 0.01);
    // Item 4 wraps to Line 2!
    try std.testing.expectApproxEqAbs(@as(f32, 0), b4.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20), b4.y, 0.01);
}

test "IFC: textAlign distribution in line boxes" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":100,"textAlign":"right"},"children":[{"id":2,"type":"column","style":{"display":"inline-flex","width":40,"height":20}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();
    const b2 = scene.find(2).?.bounds;
    // Right-aligned in 100px width: 100 - 40 = 60
    try std.testing.expectApproxEqAbs(@as(f32, 60), b2.x, 0.01);
}

test "C-SCROLL-DESCENDANT: grandchild scroll extent through visible parent (SCROLL-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","overflow":"scroll","width":100,"height":100},"children":[{"id":2,"type":"column","style":{"display":"block","overflow":"visible","width":100,"height":100},"children":[{"id":3,"type":"column","style":{"width":250,"height":300}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();
    const ext = scene.scrollExtent(1);
    // Grandchild is 250 wide and 300 high through visible child 2.
    // max_scroll_x = 250 - 100 = 150
    // max_scroll_y = 300 - 100 = 200
    try std.testing.expectApproxEqAbs(@as(f32, 150), ext.max_scroll_x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 200), ext.max_scroll_y, 0.01);

    // When parent clips/scrolls, grandchild overflow is isolated from root!
    const jsonClipped =
        \\{"id":1,"type":"root","style":{"display":"block","overflow":"scroll","width":100,"height":100},"children":[{"id":2,"type":"column","style":{"display":"block","overflow":"hidden","width":100,"height":100},"children":[{"id":3,"type":"column","style":{"width":250,"height":300}}]}]}
    ;
    var sceneClipped = try Scene.init(std.testing.allocator, jsonClipped, 100, 100);
    defer sceneClipped.deinit();
    const extClipped = sceneClipped.scrollExtent(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), extClipped.max_scroll_x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), extClipped.max_scroll_y, 0.01);
}

test "C-NESTED-WHEEL: scroll chaining across nested scroll containers (SCROLL-02)" {
    // Outer scroll container 1 (100x100) containing child 2 (height 200) -> max_scroll_y = 100
    // Inside child 2, inner scroll container 3 (at x=0, y=0, 80x80) containing grandchild 4 (height 120) -> max_scroll_y = 40
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","overflow":"scroll","width":100,"height":100},"children":[{"id":2,"type":"column","style":{"display":"flex","width":100,"height":200},"children":[{"id":3,"type":"column","style":{"display":"flex","overflow":"scroll","width":80,"height":80},"children":[{"id":4,"type":"column","style":{"width":80,"height":120}}]}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();

    var offsets = std.AutoHashMap(u32, root.ScrollOffset).init(std.testing.allocator);
    defer offsets.deinit();

    // Wheel delta_y = 60 inside inner container (x=10, y=10)
    const chained = scene.chainWheel(10, 10, 0, 60, &offsets);
    try std.testing.expect(chained);

    // Inner container (id 3) should have consumed 40 (its max_scroll_y)
    const inner_offset = offsets.get(3).?;
    try std.testing.expectApproxEqAbs(@as(f32, 40), inner_offset.y, 0.01);

    // Outer container (id 1) should have received remaining 20!
    const outer_offset = offsets.get(1).?;
    try std.testing.expectApproxEqAbs(@as(f32, 20), outer_offset.y, 0.01);
}

test "per-axis overflow: overflowX vs overflowY (SCROLL-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","overflowX":"scroll","overflowY":"hidden","width":100,"height":100},"children":[{"id":2,"type":"column","style":{"width":200,"height":200,"flexShrink":0}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();
    const root_node = scene.find(1).?.node;
    try std.testing.expect(root_node.isScrollContainerX());
    try std.testing.expect(!root_node.isScrollContainerY());
    try std.testing.expect(root_node.clipsX());
    try std.testing.expect(root_node.clipsY());

    var offsets = std.AutoHashMap(u32, root.ScrollOffset).init(std.testing.allocator);
    defer offsets.deinit();
    try offsets.put(1, .{ .x = 50, .y = 50 });

    scene.applyScrollOffsets(&offsets);
    // Y must be clamped to 0 because overflowY is not scrollable!
    try std.testing.expectApproxEqAbs(@as(f32, 50), offsets.get(1).?.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), offsets.get(1).?.y, 0.01);
}

test "input focusable vs clickable separation and tab navigation (INPUT-02)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","width":100,"height":100},"children":[{"id":2,"type":"button","clickable":false},{"id":3,"type":"column","tabIndex":0},{"id":4,"type":"column","tabIndex":-1},{"id":5,"type":"column","focusable":true}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();

    // Disabled button: not clickable, not focusable
    const btn = scene.find(2).?.node;
    try std.testing.expect(!btn.clickable);
    try std.testing.expect(!btn.isFocusable());
    try std.testing.expect(!btn.isFocusableForTab());

    // tabIndex 0: focusable, included in Tab order
    const col0 = scene.find(3).?.node;
    try std.testing.expect(col0.isFocusable());
    try std.testing.expect(col0.isFocusableForTab());

    // tabIndex -1: programmatically focusable, excluded from Tab order
    const colNeg = scene.find(4).?.node;
    try std.testing.expect(colNeg.isFocusable());
    try std.testing.expect(!colNeg.isFocusableForTab());

    // focusable true: focusable, included in Tab order
    const colFoc = scene.find(5).?.node;
    try std.testing.expect(colFoc.isFocusable());
    try std.testing.expect(colFoc.isFocusableForTab());
}

test "text_edit: grapheme clusters and pointer caret positioning (INPUT-01)" {
    const text_edit = @import("text_edit.zig");
    // UTF-8 string: "A" (1 byte), "é" (2 bytes), "e\u{0301}" (e + combining acute = 3 bytes grapheme), "B" (1 byte)
    const s = "A\u{00E9}e\u{0301}B";
    try std.testing.expectEqual(@as(usize, 0), text_edit.prevGrapheme(s, 1));
    try std.testing.expectEqual(@as(usize, 1), text_edit.nextGrapheme(s, 0));
    // next after index 1 (at \u{00E9}) advances by 2 bytes to 3
    try std.testing.expectEqual(@as(usize, 3), text_edit.nextGrapheme(s, 1));
    // next after index 3 (at e + combining acute) advances 3 bytes to 6
    try std.testing.expectEqual(@as(usize, 6), text_edit.nextGrapheme(s, 3));
    // prev from 6 goes back to 3
    try std.testing.expectEqual(@as(usize, 3), text_edit.prevGrapheme(s, 6));

    // Pointer caret positioning
    const t = root.Text{};
    const str = "hello world";
    // Each char is 0.5 * 16 = 8px wide.
    // 'h'=8, 'e'=16, 'l'=24, 'l'=32, 'o'=40
    // Click at x=18 (closer to 16 than 24) -> caret at 2 ('e')
    const pos = text_edit.positionForX(str, 18, 16, t);
    try std.testing.expectEqual(@as(usize, 2), pos);

    // Click past end -> caret at len
    const posEnd = text_edit.positionForX(str, 200, 16, t);
    try std.testing.expectEqual(str.len, posEnd);
}

// -----------------------------------------------------------------------------
// Phase E: Broaden CSS Coverage Test Fixtures
// -----------------------------------------------------------------------------

test "position: relative offsets without affecting normal flow of siblings (POS-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"position":"relative","left":20,"top":10,"width":50,"height":50}},{"id":3,"type":"column","style":{"width":50,"height":50}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();

    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;

    // Relative item 2 is offset by left=20, top=10
    try std.testing.expectApproxEqAbs(@as(f32, 20), b2.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10), b2.y, 0.01);

    // Normal flow sibling item 3 is placed immediately after item 2's un-offset position (at x=50, y=0)
    try std.testing.expectApproxEqAbs(@as(f32, 50), b3.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b3.y, 0.01);
}

test "position: absolute takes out of flow and uses positioned ancestor padding box (POS-02)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":300,"height":300},"children":[{"id":2,"type":"column","style":{"position":"relative","boxSizing":"border-box","width":100,"height":100,"borderTopWidth":5,"borderRightWidth":5,"borderBottomWidth":5,"borderLeftWidth":5,"paddingTop":10,"paddingRight":10,"paddingBottom":10,"paddingLeft":10},"children":[{"id":3,"type":"column","style":{"width":40,"height":40}},{"id":4,"type":"column","style":{"position":"absolute","right":0,"bottom":0,"width":30,"height":30}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 300);
    defer scene.deinit();

    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;
    const b4 = scene.find(4).?.bounds;

    // In-flow child 3 starts at content box of item 2: x = 0 + 5 (border) + 10 (padding) = 15
    try std.testing.expectApproxEqAbs(@as(f32, 15), b3.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 15), b3.y, 0.01);

    // Absolute child 4's containing block is padding box of item 2:
    // Item 2 padding box: left = 5, top = 5, right = 5 + (100 - 10) = 95, bottom = 95.
    // With right=0, bottom=0 and width=30, height=30:
    // x = 95 - 30 = 65, y = 95 - 30 = 65.
    try std.testing.expectApproxEqAbs(@as(f32, 65), b4.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 65), b4.y, 0.01);
    _ = b2;
}

test "position: fixed uses viewport containing block and ignores scroll offsets (POS-03)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","overflow":"scroll","width":100,"height":100},"children":[{"id":2,"type":"column","style":{"width":100,"height":300}},{"id":3,"type":"column","style":{"position":"fixed","top":10,"left":15,"width":40,"height":40}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();

    const b3Before = scene.find(3).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 15), b3Before.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10), b3Before.y, 0.01);

    // Apply scroll offset of 50px
    var offsets = std.AutoHashMap(u32, root.ScrollOffset).init(std.testing.allocator);
    defer offsets.deinit();
    try offsets.put(1, .{ .x = 0, .y = 50 });
    scene.applyScrollOffsets(&offsets);

    // Fixed child 3 must NOT be shifted by scroll offset!
    const b3After = scene.find(3).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 15), b3After.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10), b3After.y, 0.01);
}

test "position: sticky sticks within scroll container and clamps to parent (POS-04)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","overflow":"scroll","width":100,"height":100},"children":[{"id":2,"type":"column","style":{"display":"block","height":200},"children":[{"id":3,"type":"column","style":{"position":"sticky","top":10,"width":80,"height":30}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();

    // Before scroll: child 3 is at top 0
    try std.testing.expectApproxEqAbs(@as(f32, 0), scene.find(3).?.bounds.y, 0.01);

    // Scrolled by y = 25: sticky element should clamp to viewport.y + top = 10
    var offsets = std.AutoHashMap(u32, root.ScrollOffset).init(std.testing.allocator);
    defer offsets.deinit();
    try offsets.put(1, .{ .x = 0, .y = 25 });
    scene.applyScrollOffsets(&offsets);

    const b3Sticky = scene.find(3).?.bounds;
    try std.testing.expectApproxEqAbs(@as(f32, 10), b3Sticky.y, 0.01);
}

test "stacking context and z-index hit testing order (STACK-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":100,"height":100},"children":[{"id":2,"type":"button","clickable":true,"style":{"position":"absolute","left":0,"top":0,"width":50,"height":50,"zIndex":1}},{"id":3,"type":"button","clickable":true,"style":{"position":"absolute","left":0,"top":0,"width":50,"height":50,"zIndex":5}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 100, 100);
    defer scene.deinit();

    // Hit test over overlapping buttons (25, 25): should hit item 3 because zIndex 5 > 1
    const hit = scene.hitTest(25, 25);
    try std.testing.expectEqual(@as(?u32, 3), hit);

    // Verify paint order: index of item 2 must precede index of item 3
    const order = try scene.getPaintOrder(std.testing.allocator);
    defer std.testing.allocator.free(order);
    var idx2: usize = 0;
    var idx3: usize = 0;
    for (order, 0..) |item_idx, pos| {
        if (scene.items.items[item_idx].node.id == 2) idx2 = pos;
        if (scene.items.items[item_idx].node.id == 3) idx3 = pos;
    }
    try std.testing.expect(idx2 < idx3);
}

test "CSS grid track parsing, repeat, and minmax (GRID-01)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"grid","gridTemplateColumnsCss":"repeat(3, 1fr)","width":300,"height":100,"gap":0},"children":[{"id":2,"type":"column"},{"id":3,"type":"column"},{"id":4,"type":"column"}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();

    const b2 = scene.find(2).?.bounds;
    const b3 = scene.find(3).?.bounds;
    const b4 = scene.find(4).?.bounds;

    try std.testing.expectApproxEqAbs(@as(f32, 100), b2.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b3.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b4.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b2.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b3.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 200), b4.x, 0.01);
}

test "CSS grid named areas layout (GRID-02)" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"grid","gridTemplateColumnsCss":"100px 100px","gridTemplateRowsCss":"40px 60px","gridTemplateAreas":"\"header header\" \"sidebar main\"","width":200,"height":100,"gap":0},"children":[{"id":2,"type":"column","style":{"gridArea":"header"}},{"id":3,"type":"column","style":{"gridArea":"sidebar"}},{"id":4,"type":"column","style":{"gridArea":"main"}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();

    const header = scene.find(2).?.bounds;
    const sidebar = scene.find(3).?.bounds;
    const main = scene.find(4).?.bounds;

    // header spans both columns (0..2) in row 0
    try std.testing.expectApproxEqAbs(@as(f32, 0), header.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), header.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 200), header.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), header.height, 0.01);

    // sidebar at col 0, row 1
    try std.testing.expectApproxEqAbs(@as(f32, 0), sidebar.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), sidebar.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), sidebar.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 60), sidebar.height, 0.01);

    // main at col 1, row 1
    try std.testing.expectApproxEqAbs(@as(f32, 100), main.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), main.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), main.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 60), main.height, 0.01);
}

test "CSS box alignment safe vs unsafe in flex layout (ALIGN-01)" {
    // Normal center centers even if overflowing (unsafe)
    const jsonUnsafe =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","justifyContent":"center","width":50},"children":[{"id":2,"type":"column","style":{"width":100,"height":30,"flexShrink":0}}]}
    ;
    var sceneUnsafe = try Scene.init(std.testing.allocator, jsonUnsafe, 50, 50);
    defer sceneUnsafe.deinit();
    // 50 - 100 = -50 / 2 = -25
    try std.testing.expectApproxEqAbs(@as(f32, -25), sceneUnsafe.find(2).?.bounds.x, 0.01);

    // safe center clamps to 0 when overflowing!
    const jsonSafe =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","justifyContent":"safe center","width":50},"children":[{"id":2,"type":"column","style":{"width":100,"height":30,"flexShrink":0}}]}
    ;
    var sceneSafe = try Scene.init(std.testing.allocator, jsonSafe, 50, 50);
    defer sceneSafe.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 0), sceneSafe.find(2).?.bounds.x, 0.01);
}

test "CSS gradients evaluation for linear, radial, and conic (GRAD-01)" {
    const grad = root.gradient;
    // Linear gradient
    const lg_opt = try grad.parseGradient(std.testing.allocator, "linear-gradient(90deg, #ff0000 0%, #0000ff 100%)");
    try std.testing.expect(lg_opt != null);
    const lg = lg_opt.?;
    defer std.testing.allocator.free(lg.stops);
    try std.testing.expectEqual(grad.GradientKind.linear, lg.kind);
    try std.testing.expectEqual(@as(usize, 2), lg.stops.len);
    const startColor = lg.evaluate(0.0);
    try std.testing.expect(startColor[0] > 200);
    const endColor = lg.evaluate(1.0);
    try std.testing.expect(endColor[2] > 200);

    // Radial gradient
    const rg_opt = try grad.parseGradient(std.testing.allocator, "radial-gradient(circle at center, #ffffff, #000000)");
    try std.testing.expect(rg_opt != null);
    const rg = rg_opt.?;
    defer std.testing.allocator.free(rg.stops);
    try std.testing.expectEqual(grad.GradientKind.radial, rg.kind);
    try std.testing.expectEqual(@as(usize, 2), rg.stops.len);

    // Conic gradient
    const cg_opt = try grad.parseGradient(std.testing.allocator, "conic-gradient(from 0deg, #ff0000, #00ff00, #0000ff)");
    try std.testing.expect(cg_opt != null);
    const cg = cg_opt.?;
    defer std.testing.allocator.free(cg.stops);
    try std.testing.expectEqual(grad.GradientKind.conic, cg.kind);
    try std.testing.expectEqual(@as(usize, 3), cg.stops.len);
}

test "CSS 2D transforms and transformed hit testing (TRANS-01)" {
    const trans = root.transform;
    const mat = try trans.parseTransform("translate(20px, 30px) scale(2, 2)");
    try std.testing.expectApproxEqAbs(@as(f32, 20), mat.tx, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 30), mat.ty, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 2), mat.a, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 2), mat.d, 0.01);

    // Hit testing with 2D translate
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":200,"height":200},"children":[{"id":2,"type":"button","clickable":true,"style":{"width":50,"height":50,"transform":"translate(50px, 50px)"}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 200);
    defer scene.deinit();

    // Visual bounds shifted from (0, 0, 50, 50) to (50, 50, 50, 50).
    // Hit testing at (75, 75) should hit button 2!
    try std.testing.expectEqual(@as(?u32, 2), scene.hitTest(75, 75));
    // Hit testing at original (10, 10) should miss!
    try std.testing.expectEqual(@as(?u32, null), scene.hitTest(10, 10));
}

test "CSS transitions and cubic-bezier interpolation (ANIM-01)" {
    const anim = root.animation;
    const curve = anim.CubicBezier.ease;
    try std.testing.expectApproxEqAbs(@as(f32, 0), curve.solve(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), curve.solve(1), 0.001);

    // Interpolate numbers
    try std.testing.expectApproxEqAbs(@as(f32, 50), anim.interpolateNumber(0, 100, 0.5), 0.001);

    // Interpolate colors: halfway between red (255, 0, 0, 255) and blue (0, 0, 255, 255)
    const mid = anim.interpolateColor([4]u8{ 255, 0, 0, 255 }, [4]u8{ 0, 0, 255, 255 }, 0.5);
    try std.testing.expectEqual(@as(u8, 127), mid[0]);
    try std.testing.expectEqual(@as(u8, 127), mid[2]);
}

test "absolute RTL overconstraint honors right inset" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","position":"relative","direction":"rtl","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"position":"absolute","left":10,"right":20,"top":0,"width":50,"height":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    try std.testing.expectEqual(@as(f32, 130), scene.find(2).?.bounds.x);
}

test "absolute shrink-to-fit subtracts the definite inset" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","position":"relative","width":200,"height":100},"children":[{"id":2,"type":"text","text":"aaaa aaaa aaaa","style":{"position":"absolute","left":130,"top":0,"fontSize":10}}]}
    ;
    var scene = try Scene.initWithText(std.testing.allocator, json, 200, 100, .{ .measure_fn = root.text.fixedMeasurer(1.0) });
    defer scene.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 70), scene.find(2).?.bounds.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 130), scene.find(2).?.bounds.x, 0.01);
}

test "absolute auto insets retain block static position after preceding sibling" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","position":"relative","width":200,"height":100,"padding":10},"children":[{"id":2,"type":"column","style":{"height":20}},{"id":3,"type":"column","style":{"position":"absolute","width":30,"height":15}},{"id":4,"type":"column","style":{"height":10}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 220, 120);
    defer scene.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 10), scene.find(3).?.bounds.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 30), scene.find(3).?.bounds.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 30), scene.find(4).?.bounds.y, 0.01);
}

test "fixed uses transformed ancestor padding box rather than viewport" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":300,"height":200,"padding":20},"children":[{"id":2,"type":"column","style":{"display":"block","transform":"translateX(0px)","width":150,"height":100,"borderWidth":5},"children":[{"id":3,"type":"column","style":{"position":"fixed","left":10,"top":12,"width":30,"height":15}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 340, 240);
    defer scene.deinit();
    const parent = scene.find(2).?;
    const child = scene.find(3).?;
    try std.testing.expectApproxEqAbs(parent.bounds.x + 15, child.bounds.x, 0.01);
    try std.testing.expectApproxEqAbs(parent.bounds.y + 17, child.bounds.y, 0.01);
}

test "absolute flex static position uses sole-item alignment without consuming flow space" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"flex","flexDirection":"row","justifyContent":"center","alignItems":"center","width":200,"height":100},"children":[{"id":2,"type":"column","style":{"position":"absolute","width":40,"height":20}},{"id":3,"type":"column","style":{"width":60,"height":30}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 80), scene.find(2).?.bounds.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), scene.find(2).?.bounds.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 70), scene.find(3).?.bounds.x, 0.01);
}

test "right-inset shrink-to-fit still honors intrinsic minimum" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","position":"relative","width":200,"height":100},"children":[{"id":2,"type":"text","text":"aaaa aaaa aaaa","style":{"position":"absolute","right":130,"top":0,"fontSize":10}},{"id":3,"type":"text","text":"aaaa","style":{"position":"absolute","right":190,"top":40,"fontSize":10}}]}
    ;
    var scene = try Scene.initWithText(std.testing.allocator, json, 200, 100, .{ .measure_fn = root.text.fixedMeasurer(1.0) });
    defer scene.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 70), scene.find(2).?.bounds.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), scene.find(2).?.bounds.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40), scene.find(3).?.bounds.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, -30), scene.find(3).?.bounds.x, 0.01);
}

test "fixed descendant scrolls with its transformed containing block" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","width":200,"height":150},"children":[{"id":2,"type":"column","style":{"display":"block","transform":"translateX(0px)","overflow":"scroll","width":150,"height":100},"children":[{"id":3,"type":"column","style":{"position":"fixed","left":10,"top":40,"width":30,"height":15}},{"id":4,"type":"column","style":{"height":300}}]}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 150);
    defer scene.deinit();
    var offsets = std.AutoHashMap(u32, root.ScrollOffset).init(std.testing.allocator);
    defer offsets.deinit();
    try offsets.put(2, .{ .y = 30 });
    scene.applyScrollOffsets(&offsets);
    try std.testing.expectApproxEqAbs(@as(f32, 10), scene.find(3).?.bounds.y, 0.01);
}

test "opposing absolute calc and percent insets stretch within padding box" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"block","position":"relative","boxSizing":"border-box","width":200,"height":100,"borderLeftWidth":5,"borderRightWidth":5},"children":[{"id":2,"type":"column","style":{"position":"absolute","leftCss":"calc(10% - 4px)","right":10,"top":0,"bottom":0,"marginLeft":3,"marginRight":7}}]}
    ;
    var scene = try Scene.init(std.testing.allocator, json, 200, 100);
    defer scene.deinit();
    const b = scene.find(2).?.bounds;
    // Padding box is [5,195]; left=19-4=15; margins consume ten pixels.
    try std.testing.expectApproxEqAbs(@as(f32, 23), b.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 155), b.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100), b.height, 0.01);
}
