//! Backend-independent scene, box model and layout.
//!
//! `ui_core` owns geometry (`geometry.zig`), the CSS box model (`scene.Node`),
//! block/flex layout and the text metrics seam (`text.zig`). A renderer only
//! supplies a `MeasureFn` and draws the resulting items.
const std = @import("std");
pub const Tree = @import("tree.zig").Tree;
const scene = @import("scene.zig");

pub const Style = scene.Style;
pub const sizing = @import("sizing.zig");
pub const Node = scene.Node;
pub const Item = scene.Item;
pub const Scene = scene.Scene;

pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Edges = geometry.Edges;

pub const text = @import("text.zig");
pub const Text = text.Text;
pub const Metrics = text.Metrics;
pub const MeasureFn = text.MeasureFn;
pub const TextEdit = @import("text_edit.zig").TextEdit;
pub const text_edit = @import("text_edit.zig");
pub const ScrollOffset = scene.ScrollOffset;
pub const ScrollExtent = scene.ScrollExtent;
pub const layout_block = @import("layout_block.zig");
pub const layout_flex = @import("layout_flex.zig");
pub const layout_grid = @import("layout_grid.zig");
pub const layout_multicol = @import("layout_multicol.zig");
pub const selectors = @import("selectors.zig");
pub const transform = @import("transform.zig");
pub const gradient = @import("gradient.zig");
pub const paint = @import("paint.zig");
pub const interaction = @import("interaction.zig");
pub const animation = @import("animation.zig");
pub const transitions = @import("transitions.zig");
pub const media = @import("media.zig");
pub const css_scope = @import("css_scope.zig");
pub const view_transitions = @import("view_transitions.zig");

test {
    std.testing.refAllDecls(@import("tests.zig"));
    std.testing.refAllDecls(@import("phase_e_regressions.zig"));
}
