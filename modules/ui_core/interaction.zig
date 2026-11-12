//! HTML/native box interaction policy. SVG paint/fill/stroke hit testing is not
//! modeled by this renderer; SVG-only pointer-events keywords use box hits.
const std = @import("std");
const core = @import("root.zig");
const css = @import("css_syntax.zig");

/// Scene resolves inherited values while preserving explicit visible overrides
/// on descendants of hidden parents. Never skip a hidden node's subtree.
/// Collapse hides the box; flex strut/table collapse layout is not implemented.
pub fn isVisible(n: *const core.Node) bool {
    return !std.mem.eql(u8, n.style.visibility, "hidden") and !std.mem.eql(u8, n.style.visibility, "collapse");
}
pub fn acceptsPointer(n: *const core.Node) bool {
    return isVisible(n) and !std.mem.eql(u8, n.style.pointerEvents, "none");
}
pub fn acceptsFocus(n: *const core.Node) bool {
    // pointer-events:none does not remove keyboard focusability.
    return isVisible(n);
}
/// The keyword fallback after resource candidates, retaining borrowed storage.
pub fn cursorKeyword(value: []const u8) []const u8 {
    var parts = css.Tokens{ .input = value, .separators = "," };
    var result: []const u8 = "auto";
    while (parts.next()) |part| if (!std.mem.startsWith(u8, part, "url(")) {
        result = part;
    };
    return result;
}
/// First local resource spelling; native backends may try subsequent candidates.
pub fn cursorResource(value: []const u8) ?[]const u8 {
    var parts = css.Tokens{ .input = value, .separators = "," };
    while (parts.next()) |part| {
        if (!std.mem.startsWith(u8, part, "url(")) continue;
        const end = std.mem.indexOfScalar(u8, part[4..], ')') orelse continue;
        return std.mem.trim(u8, part[4 .. 4 + end], " \t\r\n\"'");
    }
    return null;
}
