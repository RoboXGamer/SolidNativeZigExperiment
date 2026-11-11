# Solid + Raylib experiment

This is an early native UI experiment. The Solid Vite plugin compiles JSX for a custom universal renderer in QuickJS-NG. Zig receives a snapshot of that tree, lays out nodes, draws them with Raylib, and sends clicks back by node ID.

`modules/ui_core` contains backend-independent scene parsing, basic row/column layout, and hit testing. `modules/solid_bridge` wraps the QuickJS runtime and snapshot/click interface. The application in `src` supplies the Raylib backend and Windows development watcher. These are separate build modules, but are not yet independently packaged libraries.

## Setup

Requires Zig 0.17.0, Node.js, pnpm, and Git. From this directory:

```powershell
git clone https://github.com/quickjs-ng/quickjs.git vendor/quickjs
git -C vendor/quickjs checkout 6a9fe9af5ca0bf7c49ae697edef44864272317d1
pnpm install --frozen-lockfile
pnpm run build:ui
zig build run
```

The application component in `ui/counter.jsx` uses Solid's usual `createSignal` and JSX. Renderer and host integration lives in `ui/renderer.js` and `ui/native.js`.

For Windows development, run `pnpm run dev:ui` in one terminal and `pnpm run dev:app` in another. The first starts Vite and a custom HMR adapter; the second builds a development bundle and starts Zig with HMR enabled. Edits to `ui/counter.jsx` are compiled by Vite's Solid plugin and delivered through Vite's HMR WebSocket; the adapter passes the update to Solid Refresh in the existing QuickJS runtime and wakes Raylib.

This is an experimental, Counter-only HMR adapter, not general module loading: Solid Refresh replaces the changed component, so its local signals, including the counter, reset while unrelated state survives. The adapter supports named imports from `solid-js` and renderer-generated imports; other component imports require an app restart. For other UI module changes, restart the app with `pnpm run dev:app`. A failed compilation does not apply an update. Run `pnpm run build:ui` before `zig build run` to rebuild the production bundle, which runs without the HMR watcher. Run commands from this directory. The generated bundles and QuickJS checkout are ignored by Git. QuickJS-NG is MIT licensed; its license is in the checkout.

Run `pnpm run test:ui` on Windows to check the counter through QuickJS without opening a window. `pnpm run test:refresh` checks Solid Refresh and the universal renderer in Node's development runtime.

Run `zig build test` for the native core tests and `pnpm run test:tree` for Solid tree/control-flow tests. The current layout supports simple rows and columns, numeric width/height, padding and gap, and basic hex colors and font size. It is not Flexbox or CSS Grid. Text width is estimated and text shaping, clipping, scrolling, keyboard focus and text input are not implemented. The bridge currently sends a full tree snapshot on each wake, not incremental mutation batches. Raylib waits for events; application timers and background updates do not yet wake the window. HMR remains Counter-only, and the requested full set of Solid primitives and components has not yet been verified.
