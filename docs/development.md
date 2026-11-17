# Development guide

The [project README](../README.md) introduces the native Solid/CSS workflow and examples. This guide records the implementation details and development commands behind that workflow.

## Setup and example selection

Requires Zig 0.17.0, Node.js, pnpm and Git on Windows. Run commands from the repository root:

```powershell
node tools/setup.mjs
pnpm install --frozen-lockfile
pnpm dev --example counter
```

`tools/setup.mjs` fetches the pinned QuickJS-NG revision. `pnpm dev` starts Vite and the native HMR adapter, builds the development bootstrap and launches the Zig application. Closing the app stops Vite; Ctrl+C stops the owned native process tree.

Choose `counter`, `css`, `states` or `tictactoe` with `--example`. Omitting it selects `css`. Examples share generated bundles and the native executable; stop one before starting another. The [examples guide](../examples/README.md) describes entry discovery and adding an example.

The two-terminal workflow uses the same example in both terminals:

```powershell
# Terminal 1
pnpm dev:ui --example counter

# Terminal 2
pnpm dev:app --example counter
```

For a production bundle and native launch:

```powershell
pnpm build:ui --example counter
zig build run
```

Run `pnpm build:ui` before `zig build run`; the bundle is embedded in the executable. Production rendering does not require a Vite server. Generated bundles, build outputs and the fetched QuickJS checkout are ignored by Git.

## Solid and the embedded host

The Solid Vite plugin compiles JSX for a custom universal renderer. The JavaScript host coalesces changes against the last acknowledged commit and sends node creation/removal plus separate layout, paint, interaction and motion inputs to Zig. Zig retains the nodes, updates affected stages and routes input back by node ID.

Application modules import `mountApp` from `@zig-ui/solid`. The repository's Vite aliases resolve that import to the local adapter; it is not an installed, published SDK. `jsconfig.json` points the editor at native JSX/style declarations.

The host uses the pinned Solid client runtime rather than reimplementing its primitives. Signals, effects, memos, deferred/optimistic state, stores/projections, actions, lifecycle hooks, contexts, children, unique IDs, lazy components/modules and control-flow components come from `solid-js`. Native layout and input operate on the resulting universal-renderer nodes. Browser DOM APIs, Node built-ins, computed dynamic import paths and top-level-await application modules require additional host support.

`modules/ui_core` owns backend-independent retained storage, box model, geometry, text metrics, block/flex/grid layout, positioning, transitions, clipping, hit testing, scrolling and UTF-8 editing state. The renderer supplies native text measurement; headless callers have a documented estimator. Each Zig module has its own build helper and standalone entry point. These modules remain local development code, without a library release.

Windows text uses DirectWrite natural layout and DPI-sized grayscale coverage. Measurement, painting, caret hit testing and horizontal selection share native layouts. The compositor keeps text at device resolution through clipping and opacity layers. See [native text implementation and validation](native-text.md).

## HMR behavior and known failures

The adapter compiles the application dependency graph through Vite and listens to Vite's HMR WebSocket. Its QuickJS module host implements imports, re-exports, literal dynamic imports, module caching, hot data, dispose/prune callbacks and dependency acceptance. Ordinary helper changes propagate to importers; Solid Refresh handles component boundaries.

Component-local state may reset when a component is replaced. An invalidated boundary remounts the application. Compile errors leave the last patch file intact; runtime failures during updates are not transactional. Changes to Zig, the renderer/host implementation or Vite configuration require an app restart.

The [HMR audit](audit/hmr-bridge.md) records reproducible failures in cleanup, failed-update recovery, async acceptance, invalidation, entry ownership, CSS order/lifetime and native API parity. Existing happy-path support does not establish reliability across those cases. The audit probes record broken behavior; they are not implemented fixes. [Tracker #364](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/364) links the follow-up work.

## CSS authoring and supported scope

Import stylesheets with `import "./app.css"` and use `class`, `className`, `classList` and `id` in JSX. Existing native properties use their CSS spelling in files, such as `background-color`, `font-size` and `grid-template-columns`. Inline style objects remain supported.

Use `<div>` for layout containers. It defaults to `display: block`; choose `display: flex` or `display: grid` in CSS. Flex containers default to a row; `flex-direction: column` stacks children vertically.

The Vite plugin uses Lightning CSS for parsing and local `@import` bundling, PostCSS for normalized declarations and pinned cssstyle definitions for shorthand expansion. The runtime resolves author styles by importance, layer, specificity and source order, with inline styles participating in the cascade. It resolves custom properties and inheritance before producing the native snapshot. Unchanged computed styles are cached.

CSS-only edits have a state-preserving update path, and removed imports have a stylesheet-pruning path. Known order/lifetime failures in those paths are tracked in the HMR audit; arbitrary edit sequences are not guaranteed to match a fresh launch.

The selector subset covers ASCII type, universal, class and ID selectors, compounds, comma lists, descendant/child/sibling combinators, and `:root`, `:hover`, `:focus`, `:active`, `:disabled`, `:enabled`, `:checked`, `:empty`. `:root` matches the retained native root. Unsupported selectors and at-rules fail the build with a diagnostic. CSS Modules are intentionally rejected.

`@media` supports viewport width/height boundaries plus the existing preference evaluator. `@supports` uses the existing host capability evaluator. Simple named cascade layers are supported; nested/scoped layer semantics and full browser query conformance are not claimed.

Local `@import` paths resolve relative to the importing stylesheet. Local `url()` paths resolve relative to the stylesheet declaring them, including inside imports; `/file.png` resolves under `public`. Assets are embedded as data URLs, so production rendering needs neither Vite nor source asset files.

The native renderer paints a single raster background with sizing (`auto`, `cover`, `contain`, lengths/percentages), two-value positioning, repeat/repeat-x/repeat-y/no-repeat, rounded clipping and alpha composition. Raster cursor URLs accept embedded PNG/JPEG/WebP images. Browser-only URL consumers, remote resources, full multi-layer image semantics, `@font-face` and `@keyframes` are outside this milestone. Accepting a stylesheet does not certify every native property/value.

`packages/solid-zig/src/css-properties.json` is generated from cssstyle 6.2.0 by `node tools/generate-css-metadata.mjs`. Keep that version pinned when using the compiler's shorthand metadata adapter; its notice is in [LICENSE-cssstyle](../packages/solid-zig/LICENSE-cssstyle).

## Input and frame scheduling

Pointer state is applied before snapshot, layout and paint in the input frame. Hover and active state include ancestors, so moving onto a button's text keeps the button hovered. Windows client cursors are retained across `WM_SETCURSOR` messages.

Native event processing is independent of painting and presentation: unchanged input wakes and cursor-only updates poll/wait through Raylib without drawing or swapping buffers. Paint updates retain measured boxes, while geometry inputs request layout. JavaScript timers and native transitions schedule frames. Paint textures are cached; tree/layout updates still rebuild the scene.

See [frame scheduling](native-frame-scheduling.md), [change discovery](change-discovery.md) and [hover measurements](hover-input-latency.md) for contracts, reproduction commands and measurement boundaries.

## Verification commands

```powershell
pnpm test
zig build test
zig build test-native
pnpm test:css:bundle
pnpm test:css:dev
pnpm build:ui --example css
zig build
pnpm test:smoke
pnpm test:hover:native
pnpm test:frames:native
```

- `pnpm test` includes the Solid/adapter, CSS, hover/change-discovery and example suites. `pnpm test:refresh` runs the Solid Refresh/universal renderer checks separately in Node's development runtime.
- `zig build test` runs UI core tests. `zig build test-native` needs a working Windows OpenGL context and checks DirectWrite contracts and native framebuffer pixels.
- CSS checks cover nested imports/URLs, source order, specificity, shorthand/longhand conflicts, layers/importance, inheritance, variables/cycles, font-relative inheritance, viewport changes and the native Vite development graph. The production bundle test clicks the reactive CSS demo button. Native framebuffer checks cover decoded background-image pixels, repetition and rounded clipping.
- `pnpm test:smoke` runs the embedded Solid/QuickJS application in a hidden native window. Build the selected UI bundle and native executable first.
- `pnpm test:hover:native` expects the CSS example and checks the real native frame pipeline. `pnpm test:frames:native` temporarily selects a scheduling fixture, exercises the event-waiting executable and restores the CSS example.

These checks cover targeted behavior. Screenshots are visual evidence of specific captures; they do not replace interaction, accessibility, physical IME or multi-monitor validation. Historical handoffs describe their own validation limits: [CSS implementation](tasks/phase-e-broaden-css.md), [app essentials](tasks/css-app-essentials-2026-11-12.md). The 2026-11-11 compatibility audit is historical; its percentages are not current measurements.

## Build details and dependency notices

QuickJS's C interpreter is compiled with `-O2` even when the Zig application uses Debug mode. To debug the interpreter without that override, use `zig build -Dquickjs-optimize=false`.

QuickJS-NG is MIT licensed; retain its checkout license when distributing the application. The CSS metadata notice is in [LICENSE-cssstyle](../packages/solid-zig/LICENSE-cssstyle). Review the fetched and pinned dependencies' notices when distributing a build.
