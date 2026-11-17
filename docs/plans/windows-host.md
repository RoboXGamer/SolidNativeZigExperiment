# Windows host implementation roadmap

Status: planned. This document groups all 28 requested Exact host module areas
into 17 implementation tasks. The clock and driver ship first in one shared PR;
Windows tasks are separately reviewable follow-ups, not additions to that PR.
Rune source references for the existing UIA/IME work are linked in
[rune-adaptation.md](rune-adaptation.md#additional-windows-references).

Local baseline: `1c75169323257fe484ec1bf14218c8c145c11e9f`.
Exact reference baseline: `65a19452362aa883024456673b723239edb47b71`.
Module presence in Exact is a source reference, not proof of complete/live
Windows qualification. No new runtime validation was performed for this plan.

## GitHub tracking

Parent: [#346](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/346).

- [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347) - Expose retained UI semantics and actions through UI Automation
- [#348](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/348) - Implement full IME composition and stable editing-session routing
- [#349](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/349) - Add system caret integration and accessible text ranges
- [#350](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/350) - Complete keyboard focus, modifier and multi-click editing conventions
- [#351](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/351) - Respect wheel settings and precision/horizontal scrolling
- [#352](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/352) - Observe system appearance, contrast, text scale and locale changes
- [#353](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/353) - Add monitor geometry and keep windows reachable across DPI changes
- [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354) - Preserve scheduled work inside native modal and resize loops
- [#355](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/355) - Add asynchronous native Open and Save file dialogs
- [#356](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/356) - Add rich clipboard, native edit menus and tooltips
- [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357) - Add app icons, single-instance activation and URL routing
- [#358](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/358) - Add tray icons and accessible status menus
- [#359](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/359) - Add jump-list tasks and opt-in desktop services
- [#360](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/360) - Add touch/pen input and convertible orientation preferences
- [#361](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/361) - Add XInput gamepad mapping and economical polling
- [#362](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/362) - Add user-requested screen capture with shared display geometry
- [#363](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/363) - Add opt-in frame diagnostics with real timing and bounded traces

## Existing foundations and scope boundaries

Preserve DirectWrite shaping/rasterization, device-scale text/compositing,
font invalidation, persistent cursors, basic focus/Tab/activation, text clipboard
operations, scroll chaining, event waiting and acknowledged phase updates.
Extend these rather than starting replacements. Keep UI core independent of
QuickJS, Raylib and Windows; Windows handles/messages belong to the host layer.

UIA, IME, keyboard/multi-click, wheel and caret are distinct behavioral tasks
over the shared input model. Native UIA semantics extend the driver's minimal
inspection model; neither implementation should create a competing tree.
Native dialogs and menus depend on modal scheduling. Activation and app identity
come before tray/jump-list services. Display coordinates come before capture.

Keep existing issues open and reference overlap: #342 owns painting/compositing,
#333 owns future SDK packaging, #44/#198/#199/#200 own CSS preference semantics,
#32 owns CSS caret-color, #65 owns cursor support and #261 owns CSS touch-action.
Host support and CSS value acceptance have separate acceptance evidence; these
new tasks neither duplicate nor silently close those tickets.

## Common implementation rules

- Place adapters under a coherent Windows host boundary, suggested
  `src/platform/windows/`, while adapting to existing build helpers. New files
  named below are proposed ownership, not code already present.
- The UI thread owns app state/QuickJS. OS/provider/worker callbacks enqueue
  owned messages with runtime/window generation rather than accessing Scene
  slices or JS values from another thread.
- Define initialize, update, cancel and destroy for each resource. Remove
  subclasses/listeners, cancel and join callbacks, then release HWND/COM/bitmap/
  timer/clipboard/provider ownership in a documented order.
- Each async result belongs to its request and live runtime/window/edit session.
  Ignore or explicitly cancel stale results after close/HMR; never target a
  reused handle solely by raw address.
- Use compact retained diffs, bounded arenas/queues and reusable capacity with
  explicit caps. UIA or shell support should not add permanent per-frame work.
  Test error cleanup and allocation failure; measure resource/handle high-water
  across repeated create/update/destroy cycles.
- Preserve logical/client/screen/device coordinate distinctions and UTF-8/
  UTF-16/grapheme offsets. Use the same shaped layouts and transforms for drawing,
  hit testing, caret and accessible bounds.
- Optional services report capabilities and failures. Implementing startup,
  protocol, hotkey, orientation or capture APIs does not enable/register/change
  those services on this workstation.
- Deterministic model/driver tests, actual desktop/API checks and physical-device
  evidence are separate. Record exactly which acceptance level passed.
- Reading and adapting Exact code requires preserving applicable license and
  attribution; links are pinned below. No blanket transplant of its Rust host.

## Recommended waves

1. W01/W02/W04 establish accessibility, composition and keyboard behavior after
   the driver; W03 adds complete caret/accessibility text behavior.
2. W05/W06/W07/W08 improve wheel/settings/displays/modal scheduling. W06/W07
   can start independently, but reconcile `windows.zig` ownership before merging.
3. W09/W10/W11 add file dialogs, edit controls and app activation. W12/W13 add
   optional tray and desktop-shell services on top.
4. W14/W15/W16 are hardware/application-driven; W17 diagnostics can follow the
   driver and support profiling without expanding existing renderer issue #342.

## Exact module coverage

| Exact modules | Planned task |
| --- | --- |
| accessibility + accessibility/model | W01 |
| ime | W02 |
| caret; accessibility text integration | W03 |
| keyboard, clicks | W04 |
| wheel | W05 |
| appearance | W06 |
| displays, placement | W07 |
| timers, modal, window integration | W08 |
| file_dialog | W09 |
| clipboard, edit_menu, tooltip | W10 |
| icon, instance, url | W11 |
| tray | W12 |
| jump_list, desktop | W13 |
| touch, orientation | W14 |
| pads, pad_poll | W15 |
| screen_capture | W16 |
| probe | W17 |

## W01: Expose retained UI semantics and actions through UI Automation

GitHub issue: [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347).

Depends on: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/windows.zig`
- `modules/ui_core/{tree,scene,interaction}.zig`
- `packages/solid-zig/src/{native.js,native.d.ts}`
- `proposed src/platform/windows/accessibility.*`

### Scope

- [ ] Extend the driver's minimal semantic projection into roles, names, values, checked/expanded/disabled states, focus and clipped screen bounds.
- [ ] Choose direct UIA or a documented C ABI adapter after checking dependencies; publish deltas and route invoke/focus/value actions through shared UI input.
- [ ] Handle native popovers/selects, focus scope/modal visibility and subtree retirement; complete text-range patterns in the dependent caret/text task.

### Edge cases

- HMR/node reuse, hidden/inert/removed controls, clipped children, DPI conversions, ambiguous names and queued actions on retired generations.
- Windows provider callbacks on other threads or during destruction; no direct QuickJS calls or borrowed scene references from those callbacks.

### Acceptance

- [ ] Narrator and a UIA inspection tool discover controls and operate name/value/focus/selection states on the real app.
- [ ] Actions and updates stay correct after removal, popover/modal changes, reload and scale changes; live UIA evidence is recorded separately from driver tests.

### Ownership and efficiency

Materialize the OS adapter only on demand, publish changed semantic nodes, marshal owning-thread actions through bounded queues and release all COM/provider references.

### Exact references

- [host/windows/src/accessibility.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/accessibility.rs)
- [host/windows/src/accessibility/model.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/accessibility/model.rs)


## W02: Implement full IME composition and stable editing-session routing

GitHub issue: [#348](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/348).

Depends on: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/{windows.zig,text_backend.cpp,text_backend.zig}`
- `modules/ui_core/text_edit.zig`
- `proposed src/platform/windows/ime.*`

### Scope

- [ ] Build on existing IMM candidate placement: track composition owner, preedit text/ranges, clause selection, commit and cancel separately from authored value.
- [ ] Deliver composition completion before focus-changing pointer actions; suppress activation shortcuts while IME consumes the same keys.
- [ ] Map UTF-16 IME offsets to native UTF-8 editing boundaries using shaped/grapheme-aware data and update candidate placement after scroll/DPI changes.

### Edge cases

- Enter commits text without submitting the form, commit followed by immediate new preedit, result-only messages, focus loss and owner removal/HMR.
- CJK and Indic input, surrogate pairs/combining sequences, selection replacement, synchronous reentrant Windows messages and shutdown during composition.

### Acceptance

- [ ] Real Windows IMEs complete compose/commit/cancel/focus-change scenarios in a focused native input without duplicated characters/actions.
- [ ] Model regressions cover stale sessions and offset mapping; record live IME proof separately from synthetic typing.

### Ownership and efficiency

Own composition buffers per editing session, reuse capacity with a cap, retain no transient COM/IMM context or scene slice, and release on blur/disposal.

### Exact references

- [host/windows/src/ime.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/ime.rs)


## W03: Add system caret integration and accessible text ranges

GitHub issue: [#349](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/349).

Depends on: [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347), [#348](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/348), [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344).

### Code ownership

- `src/{windows.zig,text_backend.cpp,text_backend.zig}`
- `modules/ui_core/text_edit.zig`
- `proposed src/platform/windows/{caret,accessibility}.*`

### Scope

- [ ] Expose OS caret position and text/selection ranges from the same shaped layouts used for paint/hit testing.
- [ ] Respect Windows blink interval/timeout and focus/activity; use the shared clock for framework-owned controlled-test blinking while validating real OS settings separately.
- [ ] Support accessible text reads, selection changes and bounds while keeping source offsets consistent across UTF-8/UTF-16/bidi runs.

### Edge cases

- Read-only/password/empty fields, selection spanning bidi fragments, scrolling/clipping/DPI, disabled blink, blur/window deactivation and field disposal.
- OS-owned blink timing must not be confused with virtual frame timing; never retain layouts after cache eviction.

### Acceptance

- [ ] Narrator/UIA text and selection patterns agree with displayed text/caret on real Windows.
- [ ] Blink and range regressions cover boundaries without permanent idle redraw; OS caret and provider objects are destroyed on teardown.

### Ownership and efficiency

Reuse shaped-layout data and bounded range scratch buffers; schedule only actual blink deadlines and invalidate only affected visual/semantic state.

### Exact references

- [host/windows/src/caret.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/caret.rs)
- [host/windows/src/accessibility.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/accessibility.rs)


## W04: Complete keyboard focus, modifier and multi-click editing conventions

GitHub issue: [#350](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/350).

Depends on: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/windows.zig`
- `modules/ui_core/{interaction,text_edit}.zig`
- `proposed src/platform/windows/{keyboard,clicks}.*`

### Scope

- [ ] Extend existing Tab/Shift+Tab/Enter/Space/editing through the shared input pipeline; distinguish physical keys, produced text, shortcuts and repeats.
- [ ] Add stable focus traversal/restoration/scopes and Windows double/triple-click word/line selection based on system click time/rectangle.
- [ ] Specify key-up/capture cleanup and interaction with composition; share semantic actions with UIA.

### Edge cases

- Non-US layouts, dead keys/AltGr, Ctrl/Shift selection, focus loss with held keys, deletion of focused nodes, disabled/hidden candidates and nested popovers.
- IME-owned Enter/Space, repeated activation, double-click interrupted by movement/time/another button and grapheme/bidi boundaries.

### Acceptance

- [ ] Keyboard-only navigation and editing pass in real Windows with at least two keyboard layouts; deterministic driver tests cover the same semantic operations.
- [ ] No stuck modifiers, duplicate activation or stale focus after blur/HMR; multi-click behavior follows user settings.

### Ownership and efficiency

Maintain compact key/focus state and cached traversal invalidated by structure/visibility, avoiding per-key full snapshots.

### Exact references

- [host/windows/src/keyboard.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/keyboard.rs)
- [host/windows/src/clicks.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/clicks.rs)


## W05: Respect wheel settings and precision/horizontal scrolling

GitHub issue: [#351](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/351).

Depends on: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/windows.zig`
- `modules/ui_core/{interaction,scene}.zig`
- `proposed src/platform/windows/wheel.*`

### Scope

- [ ] Replace the current fixed wheel*40 policy with normalized line/page/pixel deltas and Windows wheel settings.
- [ ] Support horizontal and precision deltas through existing scroll chaining/overscroll behavior; retain fractional accumulators and modifier state.

### Edge cases

- Tiny fractional deltas, direction changes, nested exhausted containers, transformed targets, stationary-pointer reconciliation and live setting changes.
- Avoid double-scaling pixel deltas; separate touch/pen contacts from wheel input and respect existing touch-action support.

### Acceptance

- [ ] Mouse wheel and precision touchpad scrolling work across nested vertical/horizontal containers and user line/page preferences.
- [ ] Driver geometry/work-count regressions confirm scrolling preserves layout and clamping; live devices are verified separately.

### Ownership and efficiency

Keep small per-device/axis accumulation state and reuse retained boxes instead of relayout for each scroll event.

### Exact references

- [host/windows/src/wheel.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/wheel.rs)


## W06: Observe system appearance, contrast, text scale and locale changes

GitHub issue: [#352](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/352).

Depends on: none; coordinate shared host file ownership.

### Code ownership

- `src/windows.zig`
- `src/{text_backend.cpp,text_backend.zig}`
- `modules/ui_core/{media_query,sizing}.zig`
- `packages/solid-zig/src/native.js`
- `proposed src/platform/windows/appearance.*`

### Scope

- [ ] Replace environment-only preference defaults with live system theme/high-contrast/reduced-motion and text-scale facts, preserving explicit driver overrides.
- [ ] Watch relevant settings, locale/time-zone/time-change and resume events; invalidate only the affected CSS, text and clock-wall-time facts.

### Edge cases

- Runtime high-contrast changes, disabled notifications/read failures, explicit author values, override removal and text scale independent of DPI.
- Wall-clock adjustment/resume must not move monotonic app time backward; avoid duplicate subclass/listener registration on reload.

### Acceptance

- [ ] Changing real Windows appearance/text-scale settings updates the running app while the driver can override/reset deterministically.
- [ ] Existing CSS #198/#199/#200 and color-scheme #44 are referenced for overlap; source presence is not treated as native settings qualification.

### Ownership and efficiency

Coalesce setting-change notifications, diff facts, release subscription tokens, and avoid polling system settings every frame.

### Exact references

- [host/windows/src/appearance.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/appearance.rs)
- [runner/src/time.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/runner/src/time.rs)

Related existing issues: #44, #198, #199, #200.


## W07: Add monitor geometry and keep windows reachable across DPI changes

GitHub issue: [#353](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/353).

Depends on: none; coordinate shared host file ownership.

### Code ownership

- `src/{windows.zig,text_backend.cpp,text_backend.zig,renderer.zig}`
- `proposed src/platform/windows/{displays,placement}.*`

### Scope

- [ ] Build on per-monitor-v2 text/rendering support with display/work-area enumeration and explicit logical/client/screen/device coordinate conversion.
- [ ] Keep the client reachable when moving across monitors, changing scale, disconnecting a display or changing work areas; publish capabilities for later capture APIs.

### Edge cases

- Negative monitor origins, mixed DPI/text scale, auto-hidden taskbars, tiny work areas, minimized/maximized/restored windows and no-display/headless runs.
- Use actual frame/client extents and avoid resize loops or double DPI scaling; retained input and UIA bounds must use the same transforms.

### Acceptance

- [ ] A real window remains usable across two monitors/scales and disconnect/reconnect; taskbar work-area behavior is recorded.
- [ ] Geometry tests cover conversions and negative origins; existing text/compositor scale checks keep passing.

### Ownership and efficiency

Cache display facts by change generation, bound handles/arrays and coalesce resize/rebuild work.

### Exact references

- [host/windows/src/displays.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/displays.rs)
- [host/windows/src/placement.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/placement.rs)


## W08: Preserve scheduled work inside native modal and resize loops

GitHub issue: [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354).

Depends on: [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344), [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/{windows.zig,event_wakeup.c}`
- `modules/solid_bridge/{root.zig,quickjs_bridge.c}`
- `proposed src/platform/windows/modal.*`

### Scope

- [ ] Integrate normal host scheduling with Windows menu, move/size and common-dialog modal loops.
- [ ] Handle stale wake generations and cancellation while preserving UI-thread QuickJS ownership, live deadlines and controlled-time isolation.

### Edge cases

- Nested/reentrant modal loops, sent versus posted messages, window destruction during callbacks and cancelled-but-already-posted timer wakes.
- No worker calls into JS, no duplicate pump or out-of-order clock samples, no forced busy polling while idle.

### Acceptance

- [ ] Timers/transitions remain responsive while dragging/resizing and showing native menus/dialogs on real Windows.
- [ ] Bounded model tests cover nested enter/exit, stale wakes and teardown; frame/idle regressions remain valid.

### Ownership and efficiency

Reuse the existing waitable wake mechanism; explicitly join callback owners and remove subclass/timer hooks before destroying their state.

### Exact references

- [host/windows/src/modal.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/modal.rs)
- [host/windows/src/timers.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/timers.rs)


## W09: Add asynchronous native Open and Save file dialogs

GitHub issue: [#355](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/355).

Depends on: [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354).

### Code ownership

- `proposed src/platform/windows/file_dialog.*`
- `modules/solid_bridge/{root.zig,quickjs_bridge.c}`
- `packages/solid-zig/src/{native.js,native.d.ts}`

### Scope

- [ ] Add typed Open/Save APIs with filters, multiselect where supported, cancellation and owned path results.
- [ ] Define UI apartment/owner-window behavior and deliver results through the normal owning-thread promise/commit path.

### Edge cases

- Unicode/long/UNC paths, missing files, overwrite confirmation, cancellation versus error, owner close/HMR and late result delivery.
- Nested dialog requests must follow a documented queue/refusal policy; never mistake a selected path for file I/O success.

### Acceptance

- [ ] Real common dialogs return correct results/cancellation and preserve background scheduling.
- [ ] Promise lifetime, filter/path conversion, failure injection and COM/handle teardown tests pass without opening real dialogs in deterministic model runs.

### Ownership and efficiency

Keep dialog-specific arenas/COM lifetimes bounded, copy selected results once into owned output and release stale request roots.

### Exact references

- [host/windows/src/file_dialog.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/file_dialog.rs)
- [host/windows/src/modal.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/modal.rs)


## W10: Add rich clipboard, native edit menus and tooltips

GitHub issue: [#356](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/356).

Depends on: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345), [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354).

### Code ownership

- `src/windows.zig`
- `modules/ui_core/text_edit.zig`
- `packages/solid-zig/src/{native.js,native.d.ts}`
- `proposed src/platform/windows/{clipboard,edit_menu,tooltip}.*`

### Scope

- [ ] Extend existing text copy/cut/paste with declared image/bitmap formats, strict format ownership and typed API results.
- [ ] Use native editing context menus and tooltip controls; derive enabled actions from the shared editor/focus state and map title text to OS tooltip behavior.

### Edge cases

- Clipboard contention/empty/unsupported or malformed formats, large images, UTF-16/NUL conversion and password/read-only fields.
- Blur/removal while a menu is open, tooltip dismissal/DPI/owner destruction and no double delivery of edit actions.

### Acceptance

- [ ] Real Windows clipboard interoperability and native menu/tooltip behavior work with other apps.
- [ ] Model tests cover format bounds, enabled states, cancellation and lifetime failures; deterministic fixtures never alter the real clipboard.

### Ownership and efficiency

Bound format sizes/decoded buffers, reuse scratch conversion space and release clipboard/bitmap/menu/window resources on every exit.

### Exact references

- [host/windows/src/clipboard.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/clipboard.rs)
- [host/windows/src/edit_menu.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/edit_menu.rs)
- [host/windows/src/tooltip.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/tooltip.rs)


## W11: Add app icons, single-instance activation and URL routing

GitHub issue: [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357).

Depends on: none; coordinate shared host file ownership.

### Code ownership

- `build.zig`
- `src/windows.zig`
- `packages/solid-zig/src/{native.js,native.d.ts}`
- `proposed src/platform/windows/{icon,instance,url}.*`

### Scope

- [ ] Embed app icon resources at appropriate title-bar/taskbar sizes and define stable app identity.
- [ ] Forward later-launch arguments to the existing instance, restore/focus its window and route incoming application locations.
- [ ] Open outgoing links through the registered URL handler; expose optional incoming protocol registration as a separately invoked installation capability.

### Edge cases

- Racing launches, stale instance endpoints, hidden/minimized windows, Unicode/quoted arguments and invalid or oversized locations.
- Activation arriving before UI readiness or during reload/close; forward exactly once and never register protocols just by importing the API.

### Acceptance

- [ ] Second launches activate the existing app and deliver exact arguments; outgoing links use the configured system handler.
- [ ] Real icon/taskbar, startup race, forwarding failure and cleanup checks are recorded.

### Ownership and efficiency

Bound single-instance messages, own activation queues, close mutex/pipe/icon handles and never keep transient command-line slices.

### Exact references

- [host/windows/src/icon.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/icon.rs)
- [host/windows/src/instance.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/instance.rs)
- [host/windows/src/url.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/url.rs)


## W12: Add tray icons and accessible status menus

GitHub issue: [#358](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/358).

Depends on: [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357), [#354](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/354), [#347](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/347).

### Code ownership

- `proposed src/platform/windows/tray.*`
- `src/windows.zig`
- `packages/solid-zig/src/{native.js,native.d.ts}`

### Scope

- [ ] Add notification-area icons with stable identity, activation and status menus; expose a deliberate close-to-tray lifecycle.
- [ ] Route icon/menu actions through shared application actions and expose accessible names/state.

### Edge cases

- Explorer restart, taskbar/DPI change, icon resource update, duplicate callbacks, keyboard invocation and window shutdown/reload.
- Distinguish hide from quit and remove icons/popups when owners disappear; don't leave a process inaccessible after close.

### Acceptance

- [ ] Tray lifecycle and mouse/keyboard menu activation work on a real desktop including Explorer recovery.
- [ ] Model tests cover stable IDs, resource replacement, action generation and complete teardown; UIA menu proof is separately recorded.

### Ownership and efficiency

Reuse sized icon resources and changed-state updates; release HICON/menu/window handles and avoid polling the tray.

### Exact references

- [host/windows/src/tray.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/tray.rs)


## W13: Add jump-list tasks and opt-in desktop services

GitHub issue: [#359](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/359).

Depends on: [#357](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/357).

### Code ownership

- `proposed src/platform/windows/{jump_list,desktop}.*`
- `src/windows.zig`
- `packages/solid-zig/src/{native.js,native.d.ts}`

### Scope

- [ ] Expose manifest-backed jump-list tasks routed through single-instance activation.
- [ ] Add explicit global-hotkey, attention and launch-at-login capabilities with registration/disposal APIs and useful errors.

### Edge cases

- Hotkey collisions, app identity/path changes, removed shortcuts, malformed quoted arguments and duplicate registration.
- Startup registration is opt-in and reversible; planning or implementing the API must not enable it on this workstation.

### Acceptance

- [ ] Real shell tasks deliver the intended route, hotkeys register/unregister cleanly and attention follows Windows behavior.
- [ ] Model tests cover idempotent update/removal and failures; startup behavior is verified only in an explicitly opted-in controlled environment.

### Ownership and efficiency

Own OS registration tokens and COM objects per application lifetime; update only changed shell items and close all handles.

### Exact references

- [host/windows/src/jump_list.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/jump_list.rs)
- [host/windows/src/desktop.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/desktop.rs)


## W14: Add touch/pen input and convertible orientation preferences

GitHub issue: [#360](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/360).

Depends on: [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/windows.zig`
- `modules/ui_core/interaction.zig`
- `proposed src/platform/windows/{touch,orientation}.*`

### Scope

- [ ] Normalize touch/pen contacts with IDs, capture, cancellation and logical coordinates through shared pointer operations.
- [ ] Avoid synthesized mouse double delivery and expose supported orientation preference on convertible devices.

### Edge cases

- Multiple contacts, capture loss, pen hover/buttons, palm/device cancellation and DPI changes mid-contact.
- Existing CSS touch-action #261 is a related semantic layer, not proof of native contact delivery; orientation is a capability on desktops.

### Acceptance

- [ ] Physical touch/pen contacts and cancellation are validated on supported hardware; synthetic contact tests cover state transitions.
- [ ] Unsupported orientation requests return a capability result and never change unrelated machine display settings.

### Ownership and efficiency

Use bounded/reusable per-contact slots and release capture/state on blur, detach and shutdown without frame polling.

### Exact references

- [host/windows/src/touch.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/touch.rs)
- [host/windows/src/orientation.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/orientation.rs)

Related existing issues: #261.


## W15: Add XInput gamepad mapping and economical polling

GitHub issue: [#361](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/361).

Depends on: [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344).

### Code ownership

- `proposed src/platform/windows/{pads,pad_poll}.*`
- `src/windows.zig`
- `packages/solid-zig/src/{native.js,native.d.ts}`

### Scope

- [ ] Add XInput connection/state queries with explicit button/axis/trigger mapping.
- [ ] Define active/inactive/hotplug polling deadlines and controlled-test recorded readings; publish device capabilities.

### Edge cases

- Disconnect while a button is held, reconnect/slot reuse, idle devices, out-of-range readings and suspension/focus changes.
- Define unsupported devices and avoid implying generic HID support; polling real devices remains separate from virtual fixture time.

### Acceptance

- [ ] A real XInput controller maps controls and reconnects correctly; recorded readings reproduce deterministic app behavior.
- [ ] Measure idle/active polling and confirm no full-speed poll loop or permanently active paint loop.

### Ownership and efficiency

Keep fixed slots and diff readings; stop/decrease polling appropriately and emit only changed state.

### Exact references

- [host/windows/src/pads.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/pads.rs)
- [host/windows/src/pad_poll.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/pad_poll.rs)


## W16: Add user-requested screen capture with shared display geometry

GitHub issue: [#362](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/362).

Depends on: [#353](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/353).

### Code ownership

- `proposed src/platform/windows/screen_capture.*`
- `packages/solid-zig/src/{native.js,native.d.ts}`
- `src/windows.zig`

### Scope

- [ ] Expose explicit display/window still capture using shared geometry and owned image results.
- [ ] Keep desktop capture separate from the driver's own framebuffer screenshot and describe unsupported/minimized/protected capture results.

### Edge cases

- Negative origins/mixed DPI, removed monitors/windows, minimized content, very large dimensions and handle reuse.
- Requests cancelled by shutdown/reload must not deliver stale images; capture must not activate or move unrelated windows.

### Acceptance

- [ ] Real captures match selected display/window dimensions and coordinates without activation.
- [ ] Dimension/overflow, resource-failure and cancellation tests release all DC/bitmap/buffer resources; capabilities describe limitations.

### Ownership and efficiency

Check dimensions and byte multiplication before allocation, bound in-flight captures and reuse bounded staging buffers without retaining frames indefinitely.

### Exact references

- [host/windows/src/screen_capture.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/screen_capture.rs)
- [host/windows/src/displays.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/displays.rs)


## W17: Add opt-in frame diagnostics with real timing and bounded traces

GitHub issue: [#363](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/363).

Depends on: [#344](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/344), [#345](https://github.com/RoboXGamer/SolidNativeZigExperiment/issues/345).

### Code ownership

- `src/{windows.zig,renderer.zig,event_wakeup.c}`
- `modules/solid_bridge/root.zig`
- `tools/driver.mjs`
- `proposed src/platform/windows/probe.*`

### Scope

- [ ] Extend current paint/layout work counts into cause-tagged real-time event, job, bridge, layout, paint and presentation traces.
- [ ] Expose versioned diagnostics through the driver with optional live-window probes; distinguish committed, submitted and presented evidence.

### Edge cases

- Virtual time versus real duration, no-paint input wakes, partial/truncated traces, GPU asynchronous work and timer/driver overhead.
- Do not infer pointer-to-photon latency from JS/CPU traces or duplicate renderer optimization issue #342.

### Acceptance

- [ ] A reproducible report separates phase costs and work counts with exact build/runtime/load conditions.
- [ ] Disabled probes have no trace allocation/queue work; enabled overhead and memory cap are measured and truncation is explicit.

### Ownership and efficiency

Use an opt-in fixed-capacity ring with dropped-record counts, stable IDs and real monotonic timestamps; stream/export outside critical input work.

### Exact references

- [host/windows/src/probe.rs](https://github.com/expo/exact/blob/65a19452362aa883024456673b723239edb47b71/host/windows/src/probe.rs)

Related existing issues: #342.
