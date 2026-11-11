const std = @import("std");
const ui = @import("root.zig");

test "official Unicode 16 extended grapheme conformance corpus" {
    var lines = std.mem.splitScalar(u8, @embedFile("unicode/GraphemeBreakTest.txt"), '\n');
    var cases: usize = 0;
    while (lines.next()) |line| {
        const content = line[0..(std.mem.indexOfScalar(u8, line, '#') orelse line.len)];
        var tokens = std.mem.tokenizeAny(u8, content, " \t\r");
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(std.testing.allocator);
        var boundaries: std.ArrayList(usize) = .empty;
        defer boundaries.deinit(std.testing.allocator);
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷")) {
                try boundaries.append(std.testing.allocator, bytes.items.len);
                continue;
            }
            if (std.mem.eql(u8, token, "×")) continue;
            const cp = try std.fmt.parseInt(u21, token, 16);
            var buffer: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(cp, &buffer);
            try bytes.appendSlice(std.testing.allocator, buffer[0..len]);
        }
        if (bytes.items.len == 0) continue;
        var offset: usize = 0;
        for (boundaries.items[1..]) |expected| {
            const actual = ui.text_edit.nextGrapheme(bytes.items, offset);
            if (expected != actual) std.debug.print("Grapheme fixture: {s}\n", .{line});
            try std.testing.expectEqual(expected, actual);
            try std.testing.expectEqual(offset, ui.text_edit.prevGrapheme(bytes.items, actual));
            offset = actual;
        }
        cases += 1;
    }
    try std.testing.expect(cases > 1000);
}

fn near(expected: f32, actual: f32) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.02);
}

test "RTL flex and unsafe cross alignment" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"display":"flex","direction":"rtl","width":200,"height":20,"alignItems":"unsafe center"},"children":[{"id":2,"type":"column","style":{"width":40,"height":40}},{"id":3,"type":"column","style":{"width":20,"height":10}}]}
    , 200, 20);
    defer scene.deinit();
    try near(160, scene.find(2).?.bounds.x);
    try near(-10, scene.find(2).?.bounds.y);
}
test "positive tabindex precedes document ordered positioned controls" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","children":[{"id":2,"type":"button","clickable":true,"style":{"position":"absolute"}},{"id":3,"type":"button","clickable":true,"tabIndex":2},{"id":4,"type":"button","clickable":true,"tabIndex":1},{"id":5,"type":"button","clickable":true}]}
    , 200, 100);
    defer scene.deinit();
    const order = try scene.getFocusOrder(std.testing.allocator);
    defer std.testing.allocator.free(order);
    try std.testing.expectEqualSlices(u32, &.{ 4, 3, 2, 5 }, order);
}
test "normal text collapses whitespace in the shared layout paint projection" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","children":[{"id":2,"type":"text","text":" one   two\nthree ","style":{"fontSize":20,"lineHeightCss":"150%"}}]}
    , 400, 100);
    defer scene.deinit();
    try std.testing.expectEqualStrings("one two three", scene.find(2).?.node.text);
    try near(30, scene.find(2).?.node.style.lineHeight.?);
}
test "step timing curves and transform interpolation avoid a collapsed midpoint" {
    const timing = ui.animation.Timing.parse("steps(4, end)");
    try near(0.25, timing.solve(0.3));
    const m = ui.animation.interpolateMatrix(ui.transform.Matrix2D.identity, ui.transform.Matrix2D.makeRotate(std.math.pi), 0.5);
    try near(1, @sqrt(m.a * m.a + m.b * m.b));
}

test "named lines and implicit column widths are consumed by placement" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"display":"grid","width":300,"height":100,"gridTemplateColumnsCss":"[start] 50px [middle] 100px [end]","gridAutoColumnsCss":"70px"},"children":[{"id":2,"type":"column","style":{"gridColumn":"middle / end"}},{"id":3,"type":"column","style":{"gridColumn":"3 / 4"}}]}
    , 300, 100);
    defer scene.deinit();
    try near(50, scene.find(2).?.bounds.x);
    try near(100, scene.find(2).?.bounds.width);
    try near(150, scene.find(3).?.bounds.x);
    try near(70, scene.find(3).?.bounds.width);
}
test "repeat minmax whitespace and auto-fit collapse differ from auto-fill" {
    const cases = .{ .{ "auto-fit", @as(f32, 300) }, .{ "auto-fill", @as(f32, 100) } };
    inline for (cases) |c| {
        const json = try std.fmt.allocPrint(std.testing.allocator, "{{\"id\":1,\"type\":\"root\",\"style\":{{\"display\":\"grid\",\"width\":300,\"height\":80,\"gridTemplateColumnsCss\":\"repeat({s}, minmax(100px, 1fr))\"}},\"children\":[{{\"id\":2,\"type\":\"column\"}}]}}", .{c[0]});
        defer std.testing.allocator.free(json);
        var scene = try ui.Scene.init(std.testing.allocator, json, 300, 80);
        defer scene.deinit();
        try near(c[1], scene.find(2).?.bounds.width);
    }
}
test "implicit rows set grid auto height and following block position" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"width":200,"height":400},"children":[{"id":2,"type":"column","style":{"display":"grid","gridTemplateColumnsCss":"100px 100px","gridAutoRowsCss":"30px 50px","rowGap":10},"children":[{"id":3,"type":"column"},{"id":4,"type":"column"},{"id":5,"type":"column"}]},{"id":6,"type":"column","style":{"height":20}}]}
    , 200, 400);
    defer scene.deinit();
    try near(90, scene.find(2).?.bounds.height);
    try near(40, scene.find(5).?.bounds.y);
    try near(50, scene.find(5).?.bounds.height);
    try near(90, scene.find(6).?.bounds.y);
}
test "grid container alignment distributes tracks on both axes" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"display":"grid","width":200,"height":200,"gridTemplateColumnsCss":"50px 50px","gridTemplateRowsCss":"40px","justifyContent":"space-between","alignContent":"center"},"children":[{"id":2,"type":"column"},{"id":3,"type":"column"}]}
    , 200, 200);
    defer scene.deinit();
    try near(150, scene.find(3).?.bounds.x);
    try near(80, scene.find(2).?.bounds.y);
}
test "absolute percentage insets resolve at positioned ancestor across static parents" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"position":"relative","width":300,"height":200},"children":[{"id":2,"type":"column","style":{"width":100,"height":100},"children":[{"id":3,"type":"column","style":{"position":"absolute","leftCss":"50%","widthCss":"50%","topCss":"50%","height":10}}]}]}
    , 300, 200);
    defer scene.deinit();
    try near(150, scene.find(3).?.bounds.x);
    try near(150, scene.find(3).?.bounds.width);
    try near(100, scene.find(3).?.bounds.y);
}
test "fixed subtree does not scroll its ordinary descendants" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"width":100,"height":100,"overflow":"scroll"},"children":[{"id":2,"type":"column","style":{"height":300}},{"id":3,"type":"column","style":{"position":"fixed","top":20,"left":10,"width":50,"height":50},"children":[{"id":4,"type":"column","style":{"height":10}}]}]}
    , 100, 100);
    defer scene.deinit();
    var offsets = std.AutoHashMap(u32, ui.ScrollOffset).init(std.testing.allocator);
    defer offsets.deinit();
    try offsets.put(1, .{ .y = 40 });
    scene.applyScrollOffsets(&offsets);
    try near(20, scene.find(4).?.bounds.y);
}
test "nested transform applies to descendant hit testing" {
    var scene = try ui.Scene.init(std.testing.allocator,
        \\{"id":1,"type":"root","style":{"width":200,"height":200},"children":[{"id":2,"type":"column","style":{"width":50,"height":50,"transform":"translate(60px, 20px) scale(2)","transformOrigin":"0 0"},"children":[{"id":3,"type":"button","clickable":true,"style":{"width":20,"height":20,"padding":0}}]}]}
    , 200, 200);
    defer scene.deinit();
    try std.testing.expectEqual(@as(?u32, 3), scene.hitTest(90, 40));
    try std.testing.expectEqual(@as(?u32, null), scene.hitTest(10, 10));
}
test "balanced shadow parser keeps rgba commas and length units" {
    const list = try ui.paint.shadows(std.testing.allocator, "2px 4px 6px -1px rgba(255, 0, 0, 0.5), inset 0 1px #000");
    defer std.testing.allocator.free(list);
    try std.testing.expectEqual(@as(usize, 2), list.len);
    try near(6, list[0].blur);
    try std.testing.expect(list[0].color[3] >= 127 and list[0].color[3] <= 128);
    try std.testing.expect(list[1].inset);
}
test "Gaussian shadow has a smooth tail outside its source box" {
    const b = try ui.paint.shadowBitmap(std.testing.allocator, 20, 20, .{ 0, 0, 0, 0 }, .{ .blur = 8 });
    defer std.testing.allocator.free(b.pixels);
    const center = b.pixels[(b.height / 2) * b.width + b.width / 2][3];
    const edge = b.pixels[(b.height / 2) * b.width + @as(usize, @intFromFloat(-b.x - 3))][3];
    try std.testing.expect(center > edge and edge > 0);
}
test "native multiline shapeLines is compiled and returns positioned lines" {
    const t = ui.Text{};
    const lines = try t.shapeLines(std.testing.allocator, "one two three", 16, 70, "normal");
    defer std.testing.allocator.free(lines);
    try std.testing.expect(lines.len > 1);
    for (lines) |line| try std.testing.expect(line.width <= 70);
}
test "runtime transitions interpolate layout color and transform then settle" {
    const old_json =
        \\{"id":1,"type":"root","style":{"width":300,"height":100,"display":"flex"},"children":[{"id":2,"type":"column","style":{"width":20,"height":20,"backgroundColor":"#ff0000","transform":"translateX(0px)"}},{"id":3,"type":"column","style":{"width":10,"height":10}}]}
    ;
    const next_json =
        \\{"id":1,"type":"root","style":{"width":300,"height":100,"display":"flex"},"children":[{"id":2,"type":"column","style":{"width":100,"height":20,"backgroundColor":"#0000ff","transform":"translateX(100px)","transition":"width 1s linear, background-color 1s linear, transform 1s linear"}},{"id":3,"type":"column","style":{"width":10,"height":10}}]}
    ;
    var old = try ui.Scene.init(std.testing.allocator, old_json, 300, 100);
    defer old.deinit();
    var next = try ui.Scene.init(std.testing.allocator, next_json, 300, 100);
    defer next.deinit();
    var timeline = ui.transitions.Timeline.init(std.testing.allocator);
    defer timeline.deinit();
    try timeline.retarget(&old, &next, 0);
    try std.testing.expect(timeline.active());
    try timeline.apply(&next, 0.5);
    try near(60, next.find(2).?.bounds.width);
    try near(60, next.find(3).?.bounds.x);
    const color = ui.gradient.parseColor(next.find(2).?.node.style.backgroundColor).?;
    try std.testing.expect(color[0] >= 126 and color[0] <= 128 and color[2] >= 126 and color[2] <= 128);
    const m = try ui.transform.parseTransform(next.find(2).?.node.style.transform);
    try near(50, m.tx);
    var final = try ui.Scene.init(std.testing.allocator, next_json, 300, 100);
    defer final.deinit();
    try timeline.apply(&final, 1.1);
    try std.testing.expect(!timeline.active());
    try near(100, final.find(2).?.bounds.width);
}

test "review: nested stacking contexts isolate descendant z-index" {
    const json =
        \\{"id":1,"type":"root","style":{"width":300,"height":300},"children":[{"id":2,"type":"column","style":{"position":"relative","zIndex":1,"width":100,"height":100},"children":[{"id":3,"type":"button","clickable":true,"style":{"position":"absolute","left":0,"top":0,"width":100,"height":100,"zIndex":100}}]},{"id":4,"type":"button","clickable":true,"style":{"position":"absolute","left":0,"top":0,"width":100,"height":100,"zIndex":2}}]}
    ;
    var scene = try ui.Scene.init(std.testing.allocator, json, 300, 300);
    defer scene.deinit();
    std.debug.print("\nnested stacking hit: expected 4, got {?}\n", .{scene.hitTest(25, 25)});
    try std.testing.expectEqual(@as(?u32, 4), scene.hitTest(25, 25));
}

test "review: grid minmax redistributes remaining fraction space" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"grid","gridTemplateColumnsCss":"minmax(200px, 1fr) 1fr","width":300,"height":100},"children":[{"id":2,"type":"column"},{"id":3,"type":"column"}]}
    ;
    var scene = try ui.Scene.init(std.testing.allocator, json, 300, 100);
    defer scene.deinit();
    std.debug.print("\ngrid widths: expected 200 + 100, got {d} + {d}\n", .{ scene.find(2).?.bounds.width, scene.find(3).?.bounds.width });
    try std.testing.expectApproxEqAbs(@as(f32, 100), scene.find(3).?.bounds.width, 0.01);
}

test "review: column auto flow wraps at explicit row boundary" {
    const json =
        \\{"id":1,"type":"root","style":{"display":"grid","gridTemplateColumnsCss":"50px 50px","gridTemplateRowsCss":"40px 40px","gridAutoFlow":"column","width":100,"height":80},"children":[{"id":2,"type":"column"},{"id":3,"type":"column"},{"id":4,"type":"column"}]}
    ;
    var scene = try ui.Scene.init(std.testing.allocator, json, 100, 80);
    defer scene.deinit();
    const b = scene.find(4).?.bounds;
    std.debug.print("\nthird grid item: expected (50,0), got ({d},{d})\n", .{ b.x, b.y });
    try std.testing.expectApproxEqAbs(@as(f32, 50), b.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.y, 0.01);
}
