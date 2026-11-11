# Solid + Raylib experiment

This is a small proof of concept: the Solid Vite plugin compiles JSX for a custom universal renderer, which maintains a JavaScript tree in QuickJS-NG; Zig reads the counter label and draws a fixed button with Raylib. It is not yet a general-purpose native renderer or layout engine.

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

Raylib waits for events; application timers and background updates do not yet wake the window. Layout, hit testing, and mapping the tree to drawing are intentionally fixed for this counter.
