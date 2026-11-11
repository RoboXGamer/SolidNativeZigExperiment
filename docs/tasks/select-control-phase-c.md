# Phase C: Select/Option Control & Async Demo Guard (SELECT-01, DEMO-01)

Branch: `feat/select-control`  
Date: 2026-11-11  
Status: **Implemented and verified**

## 1. Scope of Work

This milestone delivers Phase C of the compatibility roadmap, addressing defects **SELECT-01** (absent native `<select>` and `<option>` control) and **DEMO-01** (async race condition in state/city demo):

1. **DEMO-01 (Async Race Condition Guard):**
   - In `ui/states.jsx`, resolved the asynchronous city loading race condition where rapid changes to `selectedState` could cause out-of-order network promise resolutions to overwrite newer selections with stale data.
   - Introduced a request token / generation key (`cityRequestId`) to guard the asynchronous effect, discarding stale responses.
   - Immediately cleared city selections on state change to prevent temporary invalid state/city pairings.

2. **SELECT-01 (Select / Option Model & Interaction):**
   - Added JSX element types (`select`, `option`, `optgroup`), `NativeChangeEvent`, and updated `NativeProps` in `packages/solid-zig/src/native.d.ts`.
   - Implemented runtime registration and serialization in `packages/solid-zig/src/native.js` for `<select>` and `<option>` elements.
   - Implemented full selection model supporting controlled/uncontrolled value, option list management (dynamic addition/removal, text-as-value fallback), and disabled options/controls.
   - Added keyboard navigation (Up/Down arrows to change selection, Space/Enter to open and commit, Escape to cancel and close) and focus/clickable behavior.
   - Added native window rendering in `src/windows.zig` and QuickJS bridge key dispatching in `modules/solid_bridge/root.zig`.
   - Added closed vs open popup display management, preventing option elements from leaking into normal flow when closed.
   - Refactored `ui/states.jsx` to replace the temporary normal-flow button dropdown with native `<select>` and `<option>` elements.

---

## 2. Implementation Checklist

- [x] **DEMO-01: Async Race Condition Guard**
  - [x] Guard asynchronous city fetching with a monotonically incrementing generation key (`cityRequestId`).
  - [x] Discard responses whose token does not match the active generation key.
  - [x] Reset cities list and clear `selectedCity` immediately on state transition.
- [x] **SELECT-01: JSX Types & Intrinsic Elements**
  - [x] Added `select`, `option`, and `optgroup` to `JSX.IntrinsicElements`.
  - [x] Added `NativeChangeEvent` (`type: "change"`, `target: { id, value }`).
  - [x] Updated `NativeEvent` to include `"change"` event type.
  - [x] Added `onChange` and `selected` properties to `NativeProps`.
  - [x] Exported `dispatchClick`, `dispatchInput`, and `dispatchKey` helpers.
- [x] **SELECT-01: Selection Model & Runtime Registration**
  - [x] Configured default flex direction (`column` for select, `row` for option) and display (`none` for options when closed, `flex` when open).
  - [x] Implemented `getOptions`, `getOptionValue`, `getOptionLabel`, `getSelectValue`, and `getSelectedLabel`.
  - [x] Supported uncontrolled default selection (first enabled option) and controlled value updates.
  - [x] Supported dynamic option list updates via Solid reactive signals.
  - [x] Supported disabled options and disabled select controls.
- [x] **SELECT-01: Interaction & Keyboard Navigation**
  - [x] Clicking select toggles open/closed state.
  - [x] Clicking an option commits selection, updates value, closes popup, and dispatches `onClick`, `onInput`, and `onChange`.
  - [x] Clicking outside closes open selects.
  - [x] Keyboard `ArrowDown` / `ArrowUp` navigates through enabled options.
  - [x] Keyboard `Space` / `Enter` opens closed select; commits selection in open select.
  - [x] Keyboard `Escape` closes open select and reverts to initial selection value.
- [x] **SELECT-01: Native Rendering & Bridge Integration**
  - [x] Extended `modules/solid_bridge/root.zig` with `Runtime.key` calling `uiDispatchKey`.
  - [x] Extended `modules/ui_core/scene.zig` default padding and intrinsic dimension measurements for `select`.
  - [x] Extended `src/windows.zig` `renderScene` with select background, text, and dropdown indicator rendering.
  - [x] Extended `src/windows.zig` `keyboard` and mouse hit testing for select controls.
- [x] **SELECT-01: Demo Refactoring**
  - [x] Removed temporary `Dropdown` component with button-flow.
  - [x] Refactored `ui/states.jsx` to native `<select>` and `<option>` elements.
- [x] **Verification & Test Coverage**
  - [x] Created `packages/solid-zig/tests/select-control.mjs` covering tree serialization, value updates, change events, keyboard navigation, disabled controls, and DEMO-01 race guard.
  - [x] Added `test:select` and unified `test` scripts to `package.json`.
  - [x] Verified `npm test` passes completely (5/5 suites).
  - [x] Verified `zig test modules/ui_core/root.zig` passes completely (51/51 tests).
  - [x] Verified `npm run build:ui` and `zig build` compile cleanly without regressions.

---

## 3. Changed Files and Symbols

| File | Type | Changes / Implemented Symbols |
| --- | --- | --- |
| `packages/solid-zig/src/native.d.ts` | Types | Added `NativeChangeEvent`, added `"change"` to `NativeEvent`, added `onChange` and `selected` to `NativeProps`, registered `select`, `option`, `optgroup` in `JSX.IntrinsicElements`, declared `dispatchKey`, `dispatchClick`, `dispatchInput`. |
| `packages/solid-zig/src/native.js` | Runtime | Implemented `flexDirectionOf` and `displayOf` for `select`/`option`; added `getOptions`, `getOptionLabel`, `getOptionValue`, `getSelectValue`, `getSelectedLabel`, `isSelectedOption`, `closeAllSelects`, `dispatchSelectChange`, `dispatchClick`, `dispatchInput`, `dispatchKey`; updated `snapshot` to serialize select/option value, text, selected, open state, and default styles; wired `uiDispatchKey` in `mountApp`. |
| `modules/solid_bridge/root.zig` | Native Bridge | Added `Runtime.key(id: u32, key_name: []const u8)` calling `uiDispatchKey({d},\"{s}\")` via QuickJS evaluation. |
| `modules/ui_core/scene.zig` | Layout / Scene | Extended `Node.padding` default for `select` and `option`; extended `intrinsicWidth` and `intrinsicHeight` with fallback measurement for closed select controls. |
| `src/windows.zig` | Window / Renderer | Added `is_select` and `is_option` branches in `renderScene` for background, borders, text, and dropdown arrow; updated `keyboard` to dispatch Up/Down/Space/Enter/Escape to `Runtime.key`; updated click-outside to close open select popups. |
| `ui/states.jsx` | UI Demo | Fixed DEMO-01 with `cityRequestId` request token guard and immediate city reset; refactored to native `<select>` and `<option>` elements for State and City selection. |
| `package.json` | Tooling | Added `"test:select"` and `"test"` script running all probes and tests. |
| `packages/solid-zig/tests/select-control.mjs` | Test Fixture | Created test suite covering 7 comprehensive suites: tree serialization, default selection, option list management, change/input events, keyboard navigation, disabled controls, and async race guard. |

---

## 4. Verification Results

### A. Solid-Zig Select Test Suite
```bash
node --conditions=browser --conditions=development packages/solid-zig/tests/select-control.mjs
```
Output:
```
All select-control and async race guard tests passed successfully!
```

### B. Full NPM Test Suite (`npm test`)
```bash
npm test
```
Output:
```
> test:features
> node --conditions=browser tests/features_probe.mjs
Solid API surface test passed

> test:bridge
> node --conditions=browser --conditions=development tests/bridge_probe.mjs
JS bridge display/flexDirection defaults test passed

> test:refresh
> node --conditions=browser --conditions=development tests/refresh_probe.mjs
Solid Refresh universal renderer smoke test passed

> test:tree
> node --conditions=browser --conditions=development tests/tree_probe.mjs
Solid renderer tree and control-flow test passed

> test:select
> node --conditions=browser --conditions=development packages/solid-zig/tests/select-control.mjs
All select-control and async race guard tests passed successfully!
```

### C. Core Zig Test Suite (`zig test modules/ui_core/root.zig`)
```bash
zig test modules/ui_core/root.zig
```
Output:
```
All 51 tests passed.
```

### D. Production UI Bundle & Zig Executable Build
```bash
npm run build:ui
zig build
```
Output:
```
vite v8.3.7 building client environment for production...
src/ui-bundle.js  483.36 kB │ gzip: 144.65 kB
✓ built in 117ms
Build Summary: 6/6 steps succeeded
```
