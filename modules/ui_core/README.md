# UI core

Backend-independent Zig code for retained node storage, geometry, box styles,
text measurement, layout, clipping, hit testing, scrolling and UTF-8 editing.
The caller supplies the allocator and a text measurement callback. This module
does not depend on QuickJS, Solid, Raylib, or the operating system.

The repository's root build uses `build.zig`'s `addModule` helper. The same helper
accepts an explicit source path, target and optimization mode in another build.
The included standalone build exposes the `ui_core` module and a `test` step.

Layout currently covers the implemented block/flex subset and fixed/fr column
grid tracks. It does not claim full browser CSS compatibility. TextEdit operates
on UTF-8 codepoint boundaries; grapheme clusters, bidi selection and IME
composition need a shaping/editing backend. Text shaping and accessibility are
separate future platform integrations.

`Tree.apply` stages updates, validates graph ownership/references, then commits.
`Scene` borrows string/style storage from the tree: rebuild or discard the old
scene after a changed tree commit before reading it again. Scrolling offsets
belong to the host and are clamped to the laid-out content bounds.

No publishing or package-registry release has been performed.
