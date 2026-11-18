# Solid 2 stable upgrade plan

This plan records the Solid 2.0.0 compatibility upgrade and its validation.

Research date: 2026-11-18 IST. Local planning baseline: `e2586d51118249b8e8cf50684f2930d9462afb4e`.
The portable-build workflow landed during planning in that commit. Its production
build and outside-repository smoke belong in the upgrade's regression gate.

## Goal and delivery

Move this native Solid/Zig toolkit from **Solid 2 RC21 to Solid 2.0.0 stable**,
keeping the same JSX/CSS authoring workflow, native renderer and examples.
This is not a Solid 1 application migration: our code already uses Solid 2's
staged writes, split effects, draft stores, async primitives and universal renderer.

Deliver **one compatibility PR**, with four reviewable tasks below. Land the
runtime, universal renderer, compiler/plugin and adapter peer pins together.
Follow with a separate native async example once the stable integration is proven.
No Zig, layout-engine, paint-backend, shared-clock or driver redesign is required
by the package upgrade itself.

## Verified release and dependency set

The [official docs](https://docs.solidjs.com/) now cover Solid 2.0.
The [stable runtime release](https://github.com/solidjs/solid/releases/tag/solid-js%402.0.0)
points to upstream commit `a8186e6738b3a6a3341c561f66e9325432d6759b`.
Published npm manifests were checked directly; do not use `next` as the upgrade target.

| Package | RC21 baseline | Stable upgrade |
| --- | --- | --- |
| `solid-js` | `2.0.0-rc.21` | Exact `2.0.0` |
| `@solidjs/universal` | `2.0.0-rc.21` | Exact `2.0.0` |
| `@solidjs/vite-plugin` | `3.0.0-next.50` | Exact `3.0.0` |
| `@solidjs/web` | Implicit plugin peer at RC21 in the lockfile | Explicit build/dev peer at `2.0.0` |
| `@solidjs/signals` | Transitive RC21 engine | Exact `2.0.0` at the root for Vite deduplication |
| `@solidjs/compiler` and Windows compiler binding | Transitive prerelease toolchain | Verify resolved compiler/binding `2.0.0` |
| Vite and Babel | Vite `8.3.7`, Babel core `8.1.0`, CommonJS transform `8.0.1` | Retain these pins unless a reproduced incompatibility requires otherwise |

The root dependencies, adapter peers and lockfile move together. The stable
Vite plugin deduplicates signals from the project root. An ancestor
`node_modules` contained an older signals package and the optimizer selected it
when there was no explicit root dependency. The root pin makes both the optimizer
and Solid resolve the same stable package. Application imports still use `solid-js`.

The stable plugin declares `solid-js` and `@solidjs/web` peers at `^2.0.0`,
accepts Vite 8/9 and Babel 7/8, and depends on the stable compiler. Supplying its
web peer is a build-tool requirement; it does not change our native target to DOM.
`@solidjs/babel-plugin` is an optional peer for a deliberate Babel compiler path,
not a prerequisite for retaining the default native/OXC JSX compiler. Our existing
Babel CommonJS transform still serves the native module loader.

Solid/plugin engines require Node `>=22.12.0`; the retained Babel 8 toolchain has
the stricter range `^22.18.0 || >=24.11.0`. Record the effective toolchain requirement
in setup documentation. The local Node `26.13.0` satisfies it. These are build-tool
requirements, not a requirement to embed Node in the native application.

Manifest references: [runtime](https://registry.npmjs.org/solid-js/2.0.0),
[universal](https://registry.npmjs.org/@solidjs/universal/2.0.0),
[plugin](https://registry.npmjs.org/@solidjs/vite-plugin/3.0.0),
[signals](https://registry.npmjs.org/@solidjs/signals/2.0.0),
[compiler](https://registry.npmjs.org/@solidjs/compiler/2.0.0).

## What changed since our RC

The exact [RC21-to-stable comparison](https://github.com/solidjs/solid/compare/2105ffb8ca2fced55f5fac0763177fc93f97c2c2...a8186e6738b3a6a3341c561f66e9325432d6759b)
contains 153 commits, including documentation and web/SSR work. It is not a count
of native changes or fixes. Targeted source reads established:

- **Universal refs changed.** `packages/universal/src/universal.ts` replaces
  `runWithOwner(null, ...)` with `runRefCallback(...)`. The remaining file is
  unchanged in the inspected RC21/stable diff. This is a real lifecycle/diagnostic
  compatibility seam, not evidence that we need to rewrite `createRenderer`.
- **Flush callbacks changed.** Upstream commit `a01fd92` gives each `onFlush`
  callback its own flush. Check callback ordering, reentrant writes and the
  snapshot/commit boundary rather than assuming the RC ordering.
- **The signals engine received async/store corrections.** Held updates,
  optimistic work, dependent projections, keyed lists and disposal need semantic
  regressions through our native adapter. Do not label them new APIs introduced
  only in stable; many APIs already exist in our feature probe.
- **The Refresh entry source is unchanged.** The inspected
  `packages/solid/src/refresh/index.ts` files match. Transitive runtime/compiler
  behavior still needs testing, but there is no basis for claiming the package
  upgrade fixes our module-host reliability defects.
- **The plugin is a separate release boundary.** Its current published output
  still uses `solid-js/refresh`, retains universal compiler configuration and
  offers browser performance instrumentation. Inspect actual transformed native
  modules before changing our hard-coded external-module matching.

These are targeted observations, not a complete audit of every upstream commit.
The GitHub comparison file list is capped at 300 files and is dominated by
changesets; inspect relevant paths directly or use a full source checkout during
implementation rather than treating that list as exhaustive.

## U1. Upgrade and freeze the coordinated package graph

Depends on: a recorded RC21 baseline and a settled implementation base.

Files: `package.json`, `pnpm-lock.yaml`, `packages/solid-zig/package.json`.

- [ ] Record the base SHA, dependency graph, Node/pnpm/Zig versions, baseline
      test results and known HMR failures before changing dependencies.
- [ ] Update the direct pins and adapter peers above, including the explicit
      stable web peer needed by the plugin. Keep unrelated CSS/Vite/Babel pins.
- [ ] Resolve once, inspect peer warnings and transitive changes, then prove
      `pnpm install --frozen-lockfile` works from a clean dependency state.
- [ ] Verify one Solid/signals engine is shared by the renderer, application
      and refresh runtime. Inspect `pnpm why` output and the emitted bundles;
      a single lockfile entry alone does not prove one live runtime instance.
- [ ] Verify the Windows native/OXC compiler binding installs and loads. Keep
      compiler and binding versions aligned; record any WASI fallback explicitly.

Done when: stable dependencies install reproducibly, peers agree, and both
production and development graphs build with the native compiler.

## U2. Validate renderer, compiler output and native types

Depends on: U1.

Files: `vite.config.mjs`, `packages/solid-zig/src/renderer.js`, `native.d.ts`,
`jsx-runtime.js`, `jsx-runtime.d.ts`, `jsconfig.json`, targeted renderer fixtures.

- [ ] Retain `generate: "universal"`, `moduleName: "@zig-ui/solid/renderer"`
      and `performanceTracks: false`. Check compiled production and dev output
      against the helpers actually exported by our wrapper.
- [ ] Exercise text insertion/replacement, empty children, conditional removal,
      keyed moves, refs and reactive prop spreads. Assert retained node identity,
      parent/sibling links and cleanup; a successful bundle is insufficient.
- [ ] Test stable ref behavior: callback order, arrays, access to the creating
      pass's values, untracked reads, and forbidden primitive/cleanup creation
      inside callbacks. Own resources in component setup or an owned lifecycle
      callback; do not bypass the stable diagnostic with an ad hoc owner wrapper.
- [ ] Keep `@zig-ui/solid` as JSX type owner. The official web examples use
      `@solidjs/web`; copying that setting into this project would change our
      declaration boundary. Keep renderer-neutral `Component`/`Element` types
      from `solid-js`, native elements/styles/events from our adapter.
- [ ] Add an explicit type-check fixture for native JSX, refs, children, style
      and event types. `checkJs: false` and a successful Vite transform do not
      establish declaration compatibility. Choose/pin the checker during implementation.
- [ ] Inventory old/import-private paths in source, declarations and emitted
      code. Do not expose `solid-js/internal` or signals internals as public
      application API to silence a compiler/renderer integration error.

Done when: compiler/helper and type contracts agree and all four current examples
preserve their author-visible behavior.

## U3. Preserve the native development and Refresh boundary

Depends on: U1 and the compiler-output inventory in U2.

Files: `tools/dev.mjs`, `packages/solid-zig/src/native.js`, `module-runtime.js`,
`tests/refresh_probe.mjs`, `tests/css-dev.mjs`, `docs/audit/hmr-bridge.md`.

- [ ] Inspect Vite 3 plugin output in serve and bootstrap modes. Match the real
      runtime/refresh/renderer module IDs, including optimized paths and pnpm
      physical paths; resolve them to the embedded instances.
- [ ] Verify public and renderer-internal imports do not instantiate a second
      engine. Handle new required compiler helpers deliberately; report unsupported
      host imports clearly instead of silently compiling browser services into QuickJS.
- [ ] Keep browser DOM instrumentation and performance-track virtual clients
      out of the native runtime graph. The installed web peer is not permission
      to add `window`, `document` or browser-only devtools shims to the host.
- [ ] Re-run component replacement and cleanup, helper propagation, CSS updates,
      entry removal, syntax errors and recovery. Preserve documented state/reset
      behavior; do not promise state preservation that the adapter cannot deliver.
- [ ] Compare `tools/audit-hmr.mjs` observations against the RC baseline.
      Existing failures remain tracked under [#364](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/364).
      Separate a stable-upgrade regression from an already reproduced defect.

Done when: the known working development paths remain functional, no duplicate
runtime appears, and changed audit outcomes are explained. Full HMR rollback,
cleanup/recovery and bridge acknowledgements stay in their existing hardening tasks.

## U4. Prove scheduling and async behavior in Node and QuickJS

Depends on: U2 and U3.

Files: `tests/features.js`, `tests/features_probe.mjs`, `tests/tree_probe.mjs`,
`tests/bridge-phases.mjs`, `tests/examples.mjs`, `tests/fixtures/`, and only
necessary fixes in `modules/solid_bridge/{quickjs_bridge.c,root.zig}`.

| Edge case | Required observation |
| --- | --- |
| Staged setters and imperative reads | Reads see the committed value until the write lands; event handling, microtasks and the native snapshot agree on when it lands |
| `flush` and `onFlush` | Callback writes and nested callbacks have stable ordering; no duplicate callback, lost update or intermediate native commit |
| Effects and teardown | Compute/effect phases stay separate; superseded work and unmounted scopes cannot mutate live UI or retain callbacks |
| Ref scope | Stable ref rules hold under direct props, spread props and component replacement; cleanup still runs exactly once from the proper owner |
| Async ordering | A slower earlier result cannot overwrite the visible answer to a newer request; controlled promises cover resolution, rejection and supersession |
| Boundaries | First-load fallback, retained content while refreshing, rejection and retry work through native nodes; fallback failures reach the enclosing boundary |
| Pending and optimistic state | `latest`, `isPending`, `affects`, actions and optimistic stores agree on the displayed value; failed/cancelled work releases pending state |
| Lists and stores | Keyed reorder/removal and replacement preserve correct identity, event routing, focus and disposal; projections see updates through replaced children |
| Native event waiting | A promise/timer completion after idle produces the necessary update; an unchanged event does not force paint or presentation |
| QuickJS host surface | Production and dev bundles run using the actual provided globals and job queue; no browser/Node API is assumed from a Node-only passing test |

The host currently emulates `queueMicrotask` with promises, supplies timers and an
animation-frame timer, and drains a bounded number of QuickJS jobs per call.
Check pending-job continuation and native wake behavior around that bound; do not
paper over ordering changes by flushing every read or polling continuously.
Use controlled promise resolution for new async semantic fixtures; the full shared
clock/driver remains the separate [planned implementation](clock-driver.md).

The shared contract fixture exercises Node's client runtime and embedded QuickJS.
Native frame assertions live in the hover and scheduling probes. Async assertions
wait on controlled promises or `resolve()`, since `flush()` only drains ready work.

## Validation order and merge gate

Run the applicable baseline once, then repeat it after the upgrade. Preserve the
RC results separately from stable results. Run native/example commands serially
because generated development bundles and the default executable are shared.

```powershell
pnpm install --frozen-lockfile
pnpm test
pnpm test:css:bundle
pnpm test:css:dev
zig build test
zig build test-native

# The native hover probe expects this example.
pnpm build:ui --example css
zig build
pnpm test:smoke
pnpm test:hover:native
pnpm test:frames:native
pnpm test:solid:native

# Record diagnostic outcomes separately; this reproduces existing defects.
node --conditions=browser --conditions=development tools/audit-hmr.mjs

# Separate portable production output, followed by its outside-repository smoke.
pnpm build --example counter
pnpm test:portable
```

Build the production UI and run native startup smoke for each example
(`counter`, `css`, `states`, `tictactoe`). Run the example interaction suite,
the embedded contract fixture and the native hover regression for their distinct
interaction coverage. Use the portable smoke for a visible Windows launch.

Also run the [portable workflow](../portable-build.md) with the new compiler/runtime.
Verify its isolated bundle/native output, GUI subsystem and outside-repository
launch rather than assuming the development executable proves distributable output.
Recheck the implementation base before starting; do not ship against uncommitted
build changes absent from the PR's base.

Use this checklist to review the compatibility PR.

- [ ] Exact pins, adapter peers and frozen install agree; no prerelease engine
      or compiler is unintentionally retained in the selected graph.
- [ ] The compiler/helper/type contracts and all previously passing checks pass.
- [ ] Native QuickJS startup, interaction, async completion and idle scheduling
      work; Node-only checks are reported separately from native validation.
- [ ] The HMR failure comparison is recorded without rebranding old failures as
      fixed. New upgrade regressions are resolved or block this compatibility PR.
- [ ] Changes to bundle bytes, startup, no-work and update costs are measured
      against RC21 under the same build/example/settings if performance claims
      are made. Correctness tests or upstream benchmark claims are not local measurements.
- [ ] README status, adapter documentation and setup requirements describe the
      actually tested stable versions. Preserve old screenshot provenance unless recaptured.

Rollback is a revert of the complete compatibility PR: direct pins, adapter peers,
lockfile and required integration fixes together. Reinstall frozen dependencies
and rebuild the UI and native executable; reverting just `solid-js` leaves a mixed graph.

## Validation record

Baseline `e2586d5` (RC21), Windows x64, Node 26.13.0, pnpm 12.15.0 and Zig
0.17.0. The baseline passed JavaScript, CSS bundle and dev checks, UI core,
native framebuffer, hover and frame scheduling, and the portable build and
outside-repository smoke.

- Stable installed from a clean dependency directory with the frozen lockfile
  and strict peer checks. Bundle inspection found one signals engine in each
  of the production and development bundles, with no Solid web renderer or
  browser performance tracks. Vite loaded `compiler.win32-x64-msvc.node`.
- The strict TypeScript fixture passed with the native JSX declarations. The
  full JavaScript suite passed, including the four example bundles, CSS cache
  and bridge acknowledgement checks, and the new Solid contract fixture.
- Embedded QuickJS passed the shared contract fixture in both modes. The
  fixture checks staged writes, ref lifecycle, flush callbacks, controlled
  async ordering and retry, keyed identity, optimistic rollback and job
  continuation across the native drain budget. A compiled button update checks
  that the renderer and application share the embedded runtime.
- CSS HMR passed in the Node module host. The native development executable
  loaded the actual Vite update graph. The ten existing HMR audit reproductions
  produced identical JSON results on both versions.
- The Windows framebuffer, hover and frame scheduling probes passed. The
  scheduling fixture observed seven paints and three layouts across 130 loop
  iterations, matching the RC21 baseline.

## Follow-up: demonstrate Solid 2 async authoring natively

After the compatibility PR, add a small native async example using the official
async/boundary model: a controlled source, first-load fallback, retained results,
pending feedback, rejection and retry. Keep the existing `states` example as a
baseline while proving parity before simplifying its manual loading/request-token code.

This should show the practical benefit of Solid's async graph in our renderer.
It does not imply that QuickJS now provides browser `fetch`, router integration,
SSR or the full Solid web platform. Those require independent host support.
Observability adapters can be evaluated later; keep browser performance tracks
disabled for this native upgrade.

## Official reading mapped to our implementation

- [Solid 2 overview](https://docs.solidjs.com/): identifies the current documentation generation.
- [Migration from Solid 1](https://docs.solidjs.com/migration/from-solid-1/): useful package/type and execution-model checklist; apply only the items not already adopted in RC21.
- [Components and JSX](https://docs.solidjs.com/concepts/components-and-jsx/): ref/directive scope and component/prop contracts. Web event/style examples still require native adapter support.
- [Async reactivity](https://docs.solidjs.com/concepts/async-reactivity/): held values, request ordering and pending reads for U4 and the follow-up example.
- [Boundaries](https://docs.solidjs.com/concepts/boundaries/): loading/error/retry behavior to verify through native retained nodes.
- [Testing](https://docs.solidjs.com/guides/testing/): distinguish synchronous flush from waiting for async work; adapt assertions to our host instead of using a DOM renderer as native proof.
- [Pinned universal renderer source](https://github.com/solidjs/solid/blob/a8186e6738b3a6a3341c561f66e9325432d6759b/packages/universal/src/universal.ts) and [Refresh source](https://github.com/solidjs/solid/blob/a8186e6738b3a6a3341c561f66e9325432d6759b/packages/solid/src/refresh/index.ts): native integration contracts beyond the web-focused guides.
- Local context: [development guide](../development.md), [HMR audit](../audit/hmr-bridge.md), [frame scheduling](../native-frame-scheduling.md), [clock/driver plan](clock-driver.md).
