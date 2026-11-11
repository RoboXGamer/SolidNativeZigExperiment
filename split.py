import re

with open('modules/ui_core/root.zig') as f:
    s = f.read()

style_block = r'pub const Style = struct \{.*?\n\};\n'
m = re.search(style_block, s, re.S)
if not m:
    print('no match')
    exit(1)
s2 = re.sub(style_block, 'const style_mod = @import("style.zig");\npub const Style = style_mod.Style;\n', s, count=1, flags=re.S)
with open('modules/ui_core/scene.zig','w') as f:
    f.write(s2)

# new root re-exports
root = '''//! Backend-independent retained scene and basic row/column layout.
pub const Tree = @import("tree.zig").Tree;
const scene = @import("scene.zig");
pub const Style = scene.Style;
pub const Node = scene.Node;
pub const Rect = scene.Rect;
pub const Item = scene.Item;
pub const Scene = scene.Scene;
'''
with open('modules/ui_core/root.zig','w') as f:
    f.write(root)
print('ok')
