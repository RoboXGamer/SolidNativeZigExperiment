# Solid + Raylib experiment

This is an early native UI experiment. The Solid Vite plugin compiles JSX for a custom universal renderer in QuickJS-NG. Zig receives a snapshot of that tree, lays out nodes, draws them with Raylib, and sends clicks back by node ID.

`modules/ui_core` contains backend-independent scene parsing, box model, geometry, the text metrics seam, block/flex layout, and hit testing. It never touches a font: the renderer injects a `MeasureFn` (the Raylib backend passes `MeasureText`), and headless tests fall back to a documented estimator. `modules/solid_bridge` wraps the QuickJS runtime and snapshot/click interface. The application in `src` supplies the Raylib backend and Windows development watcher. These are separate build modules, but are not yet independently packaged libraries.

## Setup

Requires Zig 0.17.0, Node.js, pnpm, and Git. From this directory:

```powershell
git clone https://github.com/quickjs-ng/quickjs.git vendor/quickjs
git -C vendor/quickjs checkout 6a9fe9af5ca0bf7c49ae697edef44864272317d1
pnpm install --frozen-lockfile
pnpm run build:ui
zig build run
```

The application component in `ui/states.jsx` uses Solid's usual `createSignal` and JSX (an async state/city dropdown example). Renderer and host integration lives in `ui/renderer.js` and `ui/native.js`.

For Windows development, run `pnpm run dev:ui` in one terminal and `pnpm run dev:app` in another. The first starts Vite and a custom HMR adapter; the second builds a development bundle and starts Zig with HMR enabled. Edits to `ui/states.jsx` are compiled by Vite's Solid plugin and delivered through Vite's HMR WebSocket; the adapter passes the update to Solid Refresh in the existing QuickJS runtime and wakes Raylib.

This is an experimental, component-level HMR adapter, not general module loading: Solid Refresh replaces the changed component, so its local signals reset while unrelated state survives. The adapter supports named imports from `solid-js` and renderer-generated imports; other component imports require an app restart. For other UI module changes, restart the app with `pnpm run dev:app`. A failed compilation does not apply an update. Run `pnpm run build:ui` before `zig build run` to rebuild the production bundle, which runs without the HMR watcher. Run commands from this directory. The generated bundles and QuickJS checkout are ignored by Git. QuickJS-NG is MIT licensed; its license is in the checkout.

Run `pnpm run test:refresh` to check Solid Refresh and the universal renderer in Node's development runtime.

Run `zig build test` for the native core tests, `pnpm run test:tree` for Solid tree/control-flow tests, `pnpm run test:features` for the Solid 2 API surface probe, `pnpm run test:bridge` for the JS bridge's display/flex-direction defaults, and `pnpm run test:refresh` for Solid Refresh. The current layout supports block flow, flexbox (direction/wrap/grow/shrink/basis/alignment/auto margins) and basic fixed/fr grid tracks, with numeric sizes, padding, margins, and basic hex colors and font size. Text metrics come from the backend (`MeasureText`) through `ui_core`'s `MeasureFn` seam, so intrinsic widths, line heights and baselines follow the real font. It is not full CSS: floats, inline formatting (line boxes/text wrapping), full margin collapsing, percentage/auto heights, and full grid are not implemented. Text shaping, clipping, scrolling, keyboard focus and text input are not implemented beyond the basics. The bridge currently sends a full tree snapshot on each wake, not incremental mutation batches. Raylib waits for events; application timers and background updates do not yet wake the window. HMR remains component-level. The API surface probe checks that the Solid 2 primitives exist and behave in the production runtime, not that every primitive is driven end-to-end by the native renderer.
