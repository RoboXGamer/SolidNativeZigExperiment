# Solid + Raylib experiment

This is an early native UI experiment. The Solid Vite plugin compiles JSX for a custom universal renderer in QuickJS-NG. The JavaScript host compares its retained tree with the last acknowledged commit and sends changed nodes and removals to Zig. Zig retains those nodes, lays them out, draws with Raylib, and routes input back by node ID.

`modules/ui_core` contains backend-independent retained tree storage, box model, geometry, text metrics, block/flex/grid layout, positioning and transitions, clipping, hit testing, scrolling, and UTF-8 editing state. The renderer injects a `MeasureFn` (the Windows sample shares Uniscribe shaping between measurement and paint); headless callers have a documented estimator. `modules/solid_bridge` owns QuickJS jobs, timers and the change/input interface. `packages/solid-zig` contains the JavaScript renderer and module host. Each Zig module has its own build helper and standalone build entry point. The application in `src` supplies Raylib and the Windows watchers. These modules remain local development code; no library release has been made.

## Setup

Requires Zig 0.17.0, Node.js, pnpm, and Git. From this directory:

```powershell
node tools/setup.mjs
pnpm install --frozen-lockfile
pnpm run build:ui
zig build run
```

The default application is the CSS-file demo in `ui/css-demo.jsx`. Its styles start at `ui/styles/demo.css`; the async dropdown example remains in `ui/states.jsx`. `ui/native.js`, `ui/renderer.js`, and `ui/module-runtime.js` re-export the implementation in `packages/solid-zig/src`.

`jsconfig.json` points the editor at the native JSX/style declarations. New application modules can import `mountApp` from `@zig-ui/solid`; the existing relative re-exports remain available.

For Windows development, run `pnpm dev`. It starts Vite and the native HMR adapter, builds the development bootstrap, and launches the Zig application. Closing the app stops Vite; Ctrl+C stops the owned native process tree. The two-terminal workflow is also available: `pnpm dev:ui`, then `pnpm dev:app`.

The adapter compiles the application dependency graph through Vite and listens to Vite's HMR WebSocket. Its QuickJS module host supports imports, re-exports, literal dynamic imports, module caching, hot data, dispose/prune callbacks and dependency acceptance. Ordinary helper changes propagate to importers; Solid Refresh handles component boundaries. Component-local state may reset when a component is replaced. An invalidated boundary remounts the application. Compile errors leave the last patch file intact; a runtime failure during an update is not transactional. Changes to Zig, the renderer/host implementation or Vite configuration require an app restart.

The host supports Solid's client runtime rather than reimplementing its primitives. Signals, effects, memos, deferred/optimistic state, stores/projections, actions, lifecycle hooks, contexts, children, unique IDs, lazy components/modules and the requested control-flow components come from the pinned `solid-js` package. Native layout and input operate on the resulting universal-renderer nodes. Browser DOM APIs, Node built-ins, computed dynamic import paths and top-level-await application modules need additional host support.

## CSS files

Import ordinary stylesheets with `import "./app.css"` and use `class`, `className`, `classList` and `id` in JSX. Run `pnpm dev`, edit `ui/styles/demo.css`, and click the demo's toggle to test reactive class changes. Existing native properties use their CSS spelling in files (`background-color`, `font-size`, `grid-template-columns`, etc.). Inline style objects remain supported.

The Vite plugin uses Lightning CSS for parsing and local `@import` bundling, PostCSS to read normalized declarations, and pinned cssstyle definitions for shorthand expansion. The runtime resolves author styles by importance, layer, specificity and source order, with inline styles participating in the cascade. It resolves custom properties and inheritance before producing the existing native snapshot. Unchanged computed styles are cached. CSS-only edits preserve component state through the native module host; removing a CSS import prunes its stylesheet.

`css-properties.json` is generated from cssstyle 6.2.0 by `node tools/generate-css-metadata.mjs`; its notice is in `packages/solid-zig/LICENSE-cssstyle`. Keep the version pinned when using the compiler's shorthand metadata adapter.

The demo selector subset is ASCII type, universal, class and ID selectors, compounds, comma lists, descendant/child/sibling combinators, and `:root`, `:hover`, `:focus`, `:active`, `:disabled`, `:enabled`, `:checked`, `:empty`. `:root` matches the retained native root. Unsupported selectors and at-rules fail the build with a diagnostic. CSS Modules are intentionally rejected. `@media` supports viewport width/height boundaries plus the existing preference evaluator; `@supports` uses the existing host capability evaluator. Simple named cascade layers are supported; nested/scoped layer semantics and full browser query conformance are not claimed.

Local `@import` paths resolve relative to the importing stylesheet. Local `url()` paths resolve relative to the stylesheet that declares them, including inside imports; `/file.png` resolves under `public`. Assets are embedded as data URLs, so production rendering needs no Vite server or source asset files. The native renderer paints a single raster background with sizing (`auto`, `cover`, `contain`, lengths/percentages), two-value positioning, repeat/repeat-x/repeat-y/no-repeat, rounded clipping and alpha composition. Raster cursor URLs also accept embedded PNG/JPEG/WebP images. Browser-only URL consumers, remote resources, full multi-layer image semantics, `@font-face` and `@keyframes` are outside this demo milestone. Property behavior still depends on the native implementation; accepting a stylesheet does not certify every CSS property/value.

Verification commands:

```powershell
pnpm test
pnpm test:css:bundle
pnpm test:css:dev
zig build
zig build test-native
pnpm test:smoke
```

The CSS tests cover nested imports and URLs, source order, specificity, shorthand/longhand conflicts, layers and `!important`, inheritance, variables/cycles, font-relative inheritance, viewport changes, and the actual native Vite development graph. The production bundle test clicks the reactive demo button; native framebuffer tests check decoded background-image pixels, repetition and rounded clipping. CSS source errors retain the last successfully published development graph.

Run `pnpm build:ui` before `zig build run` for the production bundle. Run commands from this directory. Generated bundles and the QuickJS checkout are ignored by Git. QuickJS-NG is MIT licensed; retain its checkout license when distributing the application.

Run `pnpm run test:refresh` to check Solid Refresh and the universal renderer in Node's development runtime.

The implemented Aâ€“E paths now include the native select control, box/block/flex
layout, expanded grid/positioning/alignment, shaped text, scrolling and editing,
cached paint effects, subtree transforms/opacity and runtime transitions. Native
render tests and an actual Solid/QuickJS application smoke test supplement the
core and JavaScript suites. See [the current implementation and verification
handoff](docs/tasks/phase-e-broaden-css.md) for commands, ownership and limits.

The Windows host waits for events while idle and schedules frames for active
JavaScript timers or native transitions. Paint textures are cached; tree/layout
updates still rebuild the scene. This is a native UI experiment, not a complete
browser engine or a released desktop toolkit. Full stylesheet/cascade/query conformance,
advanced CSS families, complete controls/accessibility and full browser-oracle
conformance remain in the catalog backlog. The 2026-11-11 audit is historical;
its old percentages must not be treated as current measurements.

Everyday app typography, text overflow, elliptical corners, outlines and native
interaction/cursors are described in [the app essentials handoff](docs/tasks/css-app-essentials-2026-11-12.md).
That historical handoff records the validation limits of its batch. The CSS-file workflow has the separate checks listed above.
