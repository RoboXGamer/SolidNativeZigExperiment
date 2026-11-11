# Solid + Raylib experiment

This is an early native UI experiment. The Solid Vite plugin compiles JSX for a custom universal renderer in QuickJS-NG. The JavaScript host compares its retained tree with the last acknowledged commit and sends changed nodes and removals to Zig. Zig retains those nodes, lays them out, draws with Raylib, and routes input back by node ID.

`modules/ui_core` contains backend-independent retained tree storage, box model, geometry, text metrics, block/flex layout, basic grid columns, clipping, hit testing, scrolling, and UTF-8 editing state. The renderer injects a `MeasureFn` (the Raylib backend passes `MeasureText`); headless callers have a documented estimator. `modules/solid_bridge` owns QuickJS jobs, timers and the change/input interface. `packages/solid-zig` contains the JavaScript renderer and module host. Each Zig module has its own build helper and standalone build entry point. The application in `src` supplies Raylib and the Windows watchers. These modules remain local development code; no library release has been made.

## Setup

Requires Zig 0.17.0, Node.js, pnpm, and Git. From this directory:

```powershell
git clone https://github.com/quickjs-ng/quickjs.git vendor/quickjs
git -C vendor/quickjs checkout 6a9fe9af5ca0bf7c49ae697edef44864272317d1
pnpm install --frozen-lockfile
pnpm run build:ui
zig build run
```

The application component in `ui/states.jsx` uses Solid's usual `createSignal` and JSX (the async state/city dropdown example). `ui/native.js`, `ui/renderer.js`, and `ui/module-runtime.js` re-export the implementation in `packages/solid-zig/src`.

`jsconfig.json` points the editor at the native JSX/style declarations. New application modules can import `mountApp` from `@zig-ui/solid`; the existing relative re-exports remain available.

For Windows development, run `pnpm dev`. It starts Vite and the native HMR adapter, builds the development bootstrap, and launches the Zig application. Closing the app stops Vite; Ctrl+C stops the owned native process tree. The two-terminal workflow is also available: `pnpm dev:ui`, then `pnpm dev:app`.

The adapter compiles the application dependency graph through Vite and listens to Vite's HMR WebSocket. Its QuickJS module host supports imports, re-exports, literal dynamic imports, module caching, hot data, dispose/prune callbacks and dependency acceptance. Ordinary helper changes propagate to importers; Solid Refresh handles component boundaries. Component-local state may reset when a component is replaced. An invalidated boundary remounts the application. Compile errors leave the last patch file intact; a runtime failure during an update is not transactional. Changes to Zig, the renderer/host implementation or Vite configuration require an app restart.

The host supports Solid's client runtime rather than reimplementing its primitives. Signals, effects, memos, deferred/optimistic state, stores/projections, actions, lifecycle hooks, contexts, children, unique IDs, lazy components/modules and the requested control-flow components come from the pinned `solid-js` package. Native layout and input operate on the resulting universal-renderer nodes. Browser DOM APIs, Node built-ins, computed dynamic import paths, CSS stylesheets and top-level-await application modules need additional host support.

Run `pnpm build:ui` before `zig build run` for the production bundle. Run commands from this directory. Generated bundles and the QuickJS checkout are ignored by Git. QuickJS-NG is MIT licensed; retain its checkout license when distributing the application.

Run `pnpm run test:refresh` to check Solid Refresh and the universal renderer in Node's development runtime.

Existing checks are `zig build test`, `pnpm test:tree`, `pnpm test:features`, `pnpm test:bridge`, `pnpm test:refresh`, and `node tests/module_host.mjs`. The API surface probe is not proof that every primitive works end-to-end in the desktop application. The latest continuation has not been built, tested or run, following the request to pause testing.

The current layout supports the implemented block/flex subset and basic fixed/fr column tracks. Flex workspace now scales with the actual child count. Text widths use backend font metrics; ascent remains an estimate in the Raylib sample. The sample uses clipping-aware hit testing, vertical wheel scrolling, tab/shift-tab focus, and single-line selection/editing with clipboard shortcuts. A Windows waitable timer wakes Raylib for JavaScript deadlines; no continuous idle frame loop is needed when that worker is available. Layout is cached until tree, viewport, or scroll state changes. The JavaScript diff still walks the tree on each synchronization; a changed tree still triggers a full layout pass.

This is not full CSS or a complete desktop toolkit: floats, inline line boxes/wrapping, full margin collapsing, percentage sizing, full grid, text shaping, IME, accessibility, pointer selection and mature widgets remain work. Shadows ignore blur, colors currently accept six-digit hex, and the C bridge currently allows one live runtime per process. See [the layout feature reference](docs/html-css-reference.md) for the earlier layout inventory and remaining CSS scope; its status list predates this continuation.

The [2026-11-11 compatibility audit](C:/Users/A5IN/Coding/learning/zig/draft1/docs/compatibility-audit-2026-11-11.md) assesses commit `8873c31` against the local Taffy/Solid references and a pinned cumulative Baseline 2024 CSS inventory. It records source-derived defects, missing features, a defined planning-coverage rubric and future acceptance cases. Its percentages are source-review estimates, not measured CSS conformance. The select control is not implemented; the current demo uses a custom button dropdown.
