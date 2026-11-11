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

