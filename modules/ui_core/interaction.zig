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
    const pe = n.style.pointerEvents;
    if (std.ascii.eqlIgnoreCase(pe, "none")) return false;
    const vis = isVisible(n);
    if (std.ascii.eqlIgnoreCase(pe, "all")) return true;
    if (std.ascii.eqlIgnoreCase(pe, "visible")) return vis;
    if (std.ascii.eqlIgnoreCase(pe, "auto")) return vis;
    if (std.ascii.eqlIgnoreCase(pe, "painted") or std.ascii.eqlIgnoreCase(pe, "visiblePainted")) {
        const has_paint = (n.style.backgroundColor.len > 0 and !std.mem.eql(u8, n.style.backgroundColor, "transparent")) or
            (n.style.borderColor.len > 0 and !std.mem.eql(u8, n.style.borderColor, "transparent") and n.style.borderWidth > 0);
        if (std.ascii.eqlIgnoreCase(pe, "visiblePainted")) return vis and has_paint;
        return has_paint;
    }
    if (std.ascii.eqlIgnoreCase(pe, "fill") or std.ascii.eqlIgnoreCase(pe, "visibleFill")) {
        const has_fill = (n.style.backgroundColor.len > 0 and !std.mem.eql(u8, n.style.backgroundColor, "transparent"));
        if (std.ascii.eqlIgnoreCase(pe, "visibleFill")) return vis and has_fill;
        return has_fill;
    }
    if (std.ascii.eqlIgnoreCase(pe, "stroke") or std.ascii.eqlIgnoreCase(pe, "visibleStroke")) {
        const has_stroke = (n.style.borderWidth > 0 and n.style.borderColor.len > 0 and !std.mem.eql(u8, n.style.borderColor, "transparent"));
        if (std.ascii.eqlIgnoreCase(pe, "visibleStroke")) return vis and has_stroke;
        return has_stroke;
    }
    return vis;
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
