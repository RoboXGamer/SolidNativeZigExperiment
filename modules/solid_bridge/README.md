# Solid / QuickJS bridge

The Zig `Runtime` interface owns the embedded QuickJS-NG lifecycle, job pumping,
timer deadlines, incremental bridge commits and input dispatch. Layout and
rendering are deliberately supplied by a different module/backend.

Use the `addModule` helper in `build.zig`, passing paths to `root.zig`,
`quickjs_bridge.c`, and the pinned QuickJS-NG source directory. The standalone
build accepts `-Dquickjs-source=<absolute directory>`. QuickJS-NG is a separate
MIT-licensed dependency; retain its license when distributing compiled code.

The current C implementation permits one live Runtime per process. Creating a
second returns `RuntimeAlreadyInitialized`; it does not replace the first one.
The host must call `tick`, use `nextTimeout` to schedule a wakeup, retrieve
`changes`, apply them to its native tree and scene, then call `acknowledge` on success.
Every returned change string must be released using `freeChanges`.

The JavaScript adapter lives separately in `packages/solid-zig`. Application
code uses ordinary Solid client APIs. Node/Bun platform APIs and browser DOM
APIs are not implicitly provided by QuickJS. Timers, microtasks, console and
animation-frame scheduling are provided by the host bootstrap.

The Windows sample's timer worker only posts GLFW events; QuickJS always runs
on the UI thread. The development file watcher belongs to the sample backend,
not this library. The `reload` helper consumes the session envelope selected by
`DRAFT1_HMR_PATH`; it returns 0 for failure, 1 for application and 2 for unchanged
delivery. See [delivery and recovery](../../docs/hmr-recovery.md).

No publishing or package-registry release has been performed.
