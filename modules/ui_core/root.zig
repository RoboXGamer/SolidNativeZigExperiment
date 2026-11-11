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

test {
    std.testing.refAllDecls(@import("tests.zig"));
}
