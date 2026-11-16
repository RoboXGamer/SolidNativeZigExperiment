# Hover input and cursor fixes

The CSS demo had three independent interaction problems:

1. The native loop dispatched hover after synchronizing and laying out the scene. Event waiting could then postpone that change until another OS event.
2. Hover invalidated the global renderer tree version, forcing every stylesheet computation and native snapshot through expensive work in an unoptimized QuickJS interpreter.
3. A cursor selected with `SetCursor` was overwritten by GLFW's next `WM_SETCURSOR` handler. Hover also applied only to the hit leaf, so a button lost its hover style when its text became the target.

## Input and cursor behavior

The Windows loop applies one hover/active/focus transaction before synchronization, layout and paint. Hover and active flags cover the target's ancestor path; common ancestors retain their state while moving between descendants. `onHover` runs after the entire path is updated and only for nodes whose state changed. Focus stays on the focused control.

Leaving the client area clears hover. Changes to the retained tree reconcile interaction paths even if the target ID and physical mouse position stay the same. A layout change that moves another target beneath a stationary pointer schedules an immediate follow-up frame rather than waiting for another mouse movement.

The Windows cursor backend subclasses the existing window procedure for client-area `WM_SETCURSOR` messages. It preserves GLFW and Windows handling for non-client areas and every other message, restores the original procedure during shutdown, and retains system, raster and hidden cursor choices. Automatic cursors use an actionable ancestor when the leaf is a button's text. Explicit CSS cursor values still take precedence.

## Work avoided on pointer changes

- Stylesheet selectors and specificity are prepared when a sheet is installed. Pointer events reuse those predicates.
- The cascade cache depends on matched rules and actual inheritance inputs. Background-only changes do not invalidate all descendants. Explicit inheritance, including a `var()` fallback, also depends on the parent's computed style.
- Parsed inline declarations and variable-dependent shorthand expansions share a bounded cache of 2,048 entries.
- Unchanged native snapshots are reused. Descendant-only changes can reuse the parent's already-computed style and inherited context. Controls with derived children, such as selects and details, keep their specialized snapshot paths.
- Acknowledged, unchanged revisions return an empty patch immediately. Unacknowledged patches remain available until `uiCommit()`. Attribute, stylesheet, environment, preference, viewport and host-control changes invalidate the relevant caches.

QuickJS's vendored C interpreter is compiled with `-O2` by default, including in a Zig Debug build. The Zig application and bridge retain their selected build mode. `zig build -Dquickjs-optimize=false` removes the interpreter optimization override for debugging or matched-build measurements.

## Measured results

Measured locally on Windows with the actual CSS example, QuickJS native host, a 1,280 × 720 hidden window, Zig Debug application, and 30 sequential samples per operation. The native scene contained 24 items. Each run first acknowledged its initial snapshot. Values below are milliseconds; these small samples describe this demo and machine.

The historical hover operation alternated between button padding and its text using leave/enter dispatches and the former full-node change API. The same operation was used before and after that fix. The current probe uses pointer transactions and phase-aware changes, so new runs are not directly comparable to the historical numbers below.

| Build and operation | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Before: QuickJS `-O0`, idle change/commit | 65.1216 | 341.5724 | 451.6951 |
| Fixed: QuickJS `-O0`, idle change/commit | 0.1094 | 0.1266 | 0.1344 |
| Before: QuickJS `-O0`, legacy hover | 746.3383 | 782.8856 | 791.6556 |
| Fixed: QuickJS `-O0`, legacy hover | 27.2851 | 37.6619 | 43.9628 |
| Fixed default: QuickJS `-O2`, idle change/commit | 0.0360 | 0.0403 | 0.0434 |
| Fixed default: QuickJS `-O2`, legacy hover | 8.8862 | 9.2767 | 11.9932 |
| Fixed default: QuickJS `-O2`, batched pointer | 8.7124 | 9.4248 | 10.8452 |

The matched `-O0` rows isolate the runtime/cache changes from compiler optimization. The default `-O2` rows include the compiler setting shipped by this change. Before the fix, moving onto text changed the button background from `#4685b3` to `#356a91`; both targets now retain `#4685b3`.

These timings cover the JavaScript operation, including snapshot/diff work. They exclude native JSON parsing, layout, GPU paint, presentation and hardware input latency. The separate native regression verifies that hover is already synchronized in its input frame; it does not measure physical mouse-to-display latency. Changed scenes still use the existing native scene rebuild, and dirty revisions still scan selectors across the retained tree.

## Verification and reproduction

The checks used for this change are:

```powershell
pnpm test
pnpm test:css:bundle
zig build test
zig build test-native
pnpm build:ui --example css
zig build
pnpm test:hover:native
```

`test:hover` covers ancestor hover/active state, focus batching, sibling selectors, stable callbacks, idempotence, declaration/snapshot reuse, reparenting, inheritance after background-only hover changes, environment changes, stylesheet removal, and patch acknowledgement. `test-native` sends actual Windows cursor messages and checks text, raster and hidden cursor persistence, clickable text, and non-client delegation. The native hover smoke test injects local test coordinates into the real frame loop without moving the user's OS cursor and asserts the button's style in the entry and text-hover frames.

The actual native Vite development graph and CSS HMR were also checked with:

```powershell
pnpm exec vite build --mode native-hmr
zig build
$env:CSS_NATIVE_SMOKE = '1'
pnpm test:css:dev
Remove-Item Env:CSS_NATIVE_SMOKE
```

To run the native performance fixture:

```powershell
$env:DRAFT1_ENTRY = '/tests/fixtures/hover-probe.js'
pnpm build:ui
Remove-Item Env:DRAFT1_ENTRY
zig build
$env:SOLID_NATIVE_SMOKE = '1'
./zig-out/bin/windows.exe
Remove-Item Env:SOLID_NATIVE_SMOKE
```

Read the `HOVER_PROBE_RESULT`, `HOVER_BATCH_RESULT` and `HOVER_PROBE_STATE` log records. Use `zig build -Dquickjs-optimize=false` for the unoptimized interpreter comparison. The pre-fix reference is master commit `e01cf7b2c91ce7f52ff06b746991ac955cf1b3d1`; the fixture's optional batched section is skipped there. Restore the normal demo afterward with `pnpm build:ui --example css` followed by `zig build`.
