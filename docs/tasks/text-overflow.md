# Text and Overflow Implementation Handoff (Phase D)

Source baseline: `feat/phase-d-text-overflow` branch in `C:\Users\A5IN\.t3\worktrees\draft1\feat-phase-d-text-overf-b202802a77aea4dd`.
Follows Phase A (`docs/tasks/box-model-sizing.md`) and Phase B (`docs/tasks/flex-block-layout.md`).
References:
- `docs/compatibility-audit-2026-11-11.md` (Sections 7.6, 7.8, 7.9, Section 8 Phase D)
- Issues: #184 (Multi-line wrap and text shaping), #183 (Baseline synthesis), #280 (IFC inline-flex), #151 (Scroll extent & chaining), #245 (Focus and text input)
- W3C CSS Text Module Level 3 & CSS Inline Layout Module Level 3
- W3C CSS Overflow Module Level 3 / Level 4

---

## Scope of Work & Completed Deliverables

This phase delivers complete font metrics, multi-line wrap, Inline Formatting Context (IFC) line boxes, per-axis scrollable overflow extents, nested scroll chaining, and pointer-driven caret placement & focus management.

### Checklist: TEXT-01 .. TEXT-04 (Font Metrics, Wrap, & Baselines)

- [x] **TEXT-01: Real Font Metrics, Ascent, Descent, & Line Height.**
  - **Spec:** Accurate vertical text metrics with ascent, descent, and leading. Font size calculations must not hardcode descent to 0. Injected backend text measurer calculates accurate ascent/descent ratios.
  - **Implementation:**
    - `modules/ui_core/text.zig`: added `descent` and `leading` to `Metrics`, updated `fallback_descent_ratio = 0.20`, and `Text.ascent` / `Text.descent` methods.
    - `modules/ui_core/scene.zig`: added `lineHeight` and `lineHeightCss` to `Style`, resolved in `resolveStyle`, and propagated to natural height calculation.
    - `src/windows.zig`: updated `measureRaylib` to compute font ascent, descent, and leading using raylib font data.
  - **Fixtures:** `C-TEXT-LINES: multi-line wrap and line height synthesis (TEXT-01, TEXT-04)`.

- [x] **TEXT-02: Baseline Synthesis (First & Last Baseline).**
  - **Spec:** Support `alignItems: "first-baseline"` and `alignItems: "last-baseline"`. In a flex container or multi-line block, `first-baseline` aligns items to the baseline of their first in-flow line, and `last-baseline` aligns to their last in-flow line. Boxes without text synthesize baseline from their bottom border box edge.
  - **Implementation:** `modules/ui_core/layout_flex.zig` implements recursive `findFirstBaseline` and `findLastBaseline`, `firstBaselineOf`, and `lastBaselineOf`, supporting first and last baseline cross-alignment in flex lines.
  - **Fixtures:** `baseline synthesis: first-baseline and last-baseline alignment (TEXT-02)`.

- [x] **TEXT-03: UTF-8 Character Counting & Shaping Consistency.**
  - **Spec:** Text measurement and slicing must count UTF-8 codepoints rather than raw byte lengths, preventing multi-byte characters from ballooning width estimates or corrupting string slices.
  - **Implementation:** `modules/ui_core/text.zig` (`estimate`, `fixedMeasurer`) counts UTF-8 codepoints with `std.unicode.Utf8View`.
  - **Fixtures:** `text.test.estimate scales with length and font size`.

- [x] **TEXT-04: Multi-Line Wrapping, Hard Line Breaks, & Alignment.**
  - **Spec:** Support `whiteSpace: "normal" | "nowrap"` and `textAlign: "left" | "center" | "right"`. Multi-line text wraps at word boundaries, respects explicit `\n` line breaks, and distributes text in line boxes.
  - **Implementation:**
    - `modules/ui_core/text.zig`: `wrap` and `shapeLines` split text by newline and words, computing line boxes and widest line bounds.
    - `modules/ui_core/layout_block.zig`: inline runs wrap when exceeding container inner width and shift items according to `textAlign`.
    - `src/windows.zig`: `renderScene` draws each shaped text line aligned according to `textAlign`.
  - **Fixtures:** `C-TEXT-LINES: multi-line wrap and line height synthesis (TEXT-01, TEXT-04)`, `IFC: textAlign distribution in line boxes`.

---

### Checklist: IFC & Inline Boxes

- [x] **Inline Formatting Context with `display: inline-flex`.**
  - **Spec:** Inline-level boxes (`display: inline-flex`, `inline`, `inline-block`, and `text`) flow horizontally inside block containers, wrap to subsequent line boxes when exceeding container width, and center/right-align based on `textAlign`.
  - **Implementation:**
    - `modules/ui_core/layout_block.zig`: inline run tracking, line box height accumulation, line wrapping, and `textAlign` offset distribution.
    - `modules/ui_core/scene.zig`: allowed `inline-flex`, `inline`, `inline-block` in `appendGenerated`.
    - `packages/solid-zig/src/native.d.ts` & `native.js`: added `inline-flex`, `inline`, `inline-block` to `NativeStyle.display`.
  - **Fixtures:** `IFC: inline formatting context with inline-flex boxes (TEXT-02)`, `IFC: textAlign distribution in line boxes`.

---

### Checklist: SCROLL-01 .. SCROLL-02 (Overflow & Scrolling)

- [x] **SCROLL-01: Per-Axis Scrollable Overflow Extent (C-SCROLL-DESCENDANT).**
  - **Spec:** Support independent `overflowX` and `overflowY` (and two-value `overflow: "scroll hidden"` shorthand). Scrollable extent (`scrollExtent`) must traverse through intermediate descendant boxes with `overflow: visible` to include overflowing grandchildren, while stopping when an ancestor clips or scrolls.
  - **Implementation:**
    - `modules/ui_core/style.zig` & `scene.zig`: added `overflowX`, `overflowY`, `scrollbarGutter`, `scrollbarWidth`.
    - `scene.zig`: `effectiveOverflowX()`, `effectiveOverflowY()`, `isScrollContainerX()`, `isScrollContainerY()`, `clipsX()`, `clipsY()`.
    - `scene.zig`: `scrollExtent` traverses descendant subtree, tracking intermediate visibility clipping.
    - `scene.zig`: `applyScrollOffsets` clamps offsets per-axis according to `isScrollContainerX()` and `isScrollContainerY()`.
  - **Fixtures:** `C-SCROLL-DESCENDANT: grandchild scroll extent through visible parent (SCROLL-01)`, `per-axis overflow: overflowX vs overflowY (SCROLL-01)`.

- [x] **SCROLL-02: Nested Scroll Chaining (C-NESTED-WHEEL).**
  - **Spec:** Wheel events targeted inside nested scroll containers must consume delta up to the inner container's max scroll extent; any unconsumed delta must chain upward to parent scroll containers.
  - **Implementation:** `modules/ui_core/scene.zig`: `chainWheel` traverses hit-tested scroll containers from deepest to outermost, consuming delta at each level and propagating the remainder.
  - **Fixtures:** `C-NESTED-WHEEL: scroll chaining across nested scroll containers (SCROLL-02)`.

---

### Checklist: INPUT-01 .. INPUT-02 (Input, Selection, & Focus)

- [x] **INPUT-01: Grapheme Clusters, Pointer Caret Positioning, & Selection.**
  - **Spec:** Caret navigation must step by extended grapheme clusters rather than single bytes, keeping combining marks attached to base characters. Clicking or dragging over text must place the caret at the closest grapheme boundary.
  - **Implementation:**
    - `modules/ui_core/text_edit.zig`: `isCombining`, `prevCodepoint`, `prevGrapheme`, `nextGrapheme`.
    - `modules/ui_core/text_edit.zig`: `positionForX` maps relative X coordinate to nearest grapheme index.
    - `src/windows.zig`: mouse button pressed and mouse dragging update caret position and text selection using `positionForX`.
  - **Fixtures:** `text_edit: grapheme clusters and pointer caret positioning (INPUT-01)`.

- [x] **INPUT-02: Focusable vs Clickable Separation & Tab Navigation.**
  - **Spec:** Separate `clickable` from `focusable`. Buttons and inputs are focusable and clickable unless disabled. Elements with `tabIndex >= 0` or `focusable: true` participate in Tab order, while `tabIndex < 0` is focusable programmatically but excluded from Tab order. Space key activates focused buttons.
  - **Implementation:**
    - `modules/ui_core/tree.zig`: added `focusable` and `tabIndex` to `FlatNode`.
    - `modules/ui_core/scene.zig`: `isFocusable` and `isFocusableForTab`.
    - `packages/solid-zig/src/native.d.ts` & `native.js`: serialization of `tabIndex` and `focusable`.
    - `src/windows.zig`: Tab navigation uses `isFocusableForTab()`, Space key activates focused button.
  - **Fixtures:** `input focusable vs clickable separation and tab navigation (INPUT-02)`, `packages/solid-zig/tests/text-overflow.mjs`.

---

## Verification Summary

- **Zig regression test suite:** `zig test modules/ui_core/root.zig` passes 74/74 tests.
- **Node universal test suite:** `npm test` passes all tests (`test:features`, `test:bridge`, `test:refresh`, `test:tree`, `test:packages`).
- **UI bundle build:** `npm run build:ui` succeeds cleanly (Vite client build).
