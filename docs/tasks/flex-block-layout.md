# Flex and Block Layout Implementation Handoff (Phase B)

Source baseline: `feat/flex-block-layout` branch in `C:\Users\A5IN\Coding\learning\zig\draft1`.
Follows Phase A foundation (`docs/tasks/box-model-sizing.md`).
References:
- `docs/compatibility-audit-2026-11-11.md` (Sections 4.2, 4.3, 8 Phase B)
- Local Taffy reference at `C:/Users/A5IN/Coding/reference/taffy` (specifically `compute/flexbox.rs` and `tree/layout.rs`)
- W3C CSS Flexible Box Layout Module Level 1 (§9.7 Resolving Flexible Lengths)
- W3C CSS Box Model / CSS 2.1 §10.3 (Block horizontal sizing) & §8.3.1 (Margin collapsing)

---

## Scope of Work & Completed Deliverables

This phase resolves all defect obligations for **Flex Formatting** (`FLEX-01` through `FLEX-07`, Issues #87, #88) and **Block Formatting** (`BLOCK-01` through `BLOCK-06`, Issues #156, #282).

### Checklist: FLEX-01 .. FLEX-07

- [x] **FLEX-01: Fractional Flex Factors (Sum < 1).**
  - **Spec:** W3C Flexbox §9.7 step 4. When the sum of flex grow factors (or shrink factors) is strictly less than 1, the distributed free space is multiplied by the factor sum, leaving the remaining fraction of available free space unconsumed.
  - **Implementation:** In `modules/ui_core/layout_flex.zig` (`resolveFlexibleLengths`), free space is scaled by `grow_factor_sum` / `shrink_factor_sum` when `< 1.0`.
  - **Fixtures:** `C-PARTIAL-GROW: partial flex factors sum < 1 (FLEX-01)`, `partial flex shrink factor sum < 1 (FLEX-01)`.

- [x] **FLEX-02: Decoupled Bases, Hypothetical Sizes, & Iterative Freezing Loop.**
  - **Spec:** W3C Flexbox §9.7 steps 1–4 / Taffy `resolve_flexible_lengths`. Distinguish raw `flex-basis`, `hypothetical_main_size` (clamped to min/max), and target sizes. Compute initial free space as container inner main size minus sum of raw flex bases. Check for min/max violations across non-frozen items, freeze violating items at their clamped constraint bounds, adjust target free space, and repeat loop until all remaining items are unconstrained or space is zero.
  - **Implementation:** `resolveFlexibleLengths` in `modules/ui_core/layout_flex.zig` executes the spec iterative loop with `FlexItemState` tracking `flex_basis`, `hypothetical_size`, `target_size`, `min_size`, `max_size`, and `frozen`.
  - **Fixtures:** `C-BASIS-MIN: raw flex bases separate from hypothetical sizes (FLEX-02)`, `flex iterative loop freezing violating items (FLEX-02)`.

- [x] **FLEX-03: Decoupled Intrinsic Contributions.**
  - **Spec:** Intrinsic sizes (`min-content`, `max-content`) of flex items must be computed without blindly recurring using the container's `flexDirection` for nested block/grid/text children.
  - **Implementation:** In `modules/ui_core/layout_flex.zig`, `minContentWidth` and `maxContentWidth` measure children according to their own formatting contexts (`display: block`, `grid`, `text`), properly accounting for outer margin contributions.
  - **Fixtures:** `flex-basis content uses intrinsic max-content width`, `flex shrink stops at min-content width`.

- [x] **FLEX-04: Single-Line Definite Cross Sizing & Wrap-Reverse.**
  - **Spec:** In a single-line flex container (`flexWrap: nowrap`), the line cross size fills the definite container cross size independently of `alignContent`. In `flexWrap: wrap-reverse`, cross-axis positioning and alignment are inverted, even for a single line.
  - **Implementation:** In `modules/ui_core/layout_flex.zig`, single line with definite cross size sets `line_cross[0] = cross_avail` (`C-NOWRAP-CROSS`). `wrap-reverse` reverses line ordering and inverts item cross-alignment offsets.
  - **Fixtures:** `C-NOWRAP-CROSS: single-line definite cross size fills line (FLEX-04)`, `wrap-reverse single line reverses cross position (FLEX-04)`.

- [x] **FLEX-05: Auto Cross-Axis Remeasurement After Main Flexing.**
  - **Spec:** Items with `auto` cross size (especially text or height-dependent children with aspect ratio or wrapping content) cannot know their final cross size until their main size is flexed.
  - **Implementation:** After main-axis flexible lengths are resolved, `layoutFlex` remeasures children having auto cross sizes (`child.style.height == null`) using their resolved flexed width via `naturalHeightForWidth`.
  - **Fixtures:** `cross size remeasurement after main flexing (FLEX-05)`.

- [x] **FLEX-06: Document Order Preserved for Semantic / Tab Focus Sequence.**
  - **Spec:** Visual reordering via CSS `order` must affect visual placement coordinates but must NOT change document tree or semantic Tab focus order in `scene.items`.
  - **Implementation:** Children are sorted by `order` solely for visual coordinate layout. Emitting into `scene.items` is performed in original document order (`n.children`), decoupling visual bounds from focus sequence.
  - **Fixtures:** `visual order preserves document focus sequence (FLEX-06)`.

- [x] **FLEX-07: Flex Value Grammar & Gap Support.**
  - **Spec:** Full CSS `flex` shorthand parser (`flex: "1 20px"`, `flex: "20px 1"`, `flex: 2`, `none`, `auto`, `initial`), typed string `flexBasis` (`"20px"`, `"50%"`, keywords `content`, `max-content`, `min-content`), `flexFlow` shorthand (`row wrap`), and `rowGap` / `columnGap`.
  - **Implementation:**
    - `packages/solid-zig/src/native.js`: robust `flex` shorthand parser, `flexBasis` CSS unit preservation, `flexFlow` expansion, multi-value `gap` expansion.
    - `modules/ui_core/style.zig` & `scene.zig`: added `rowGap`, `columnGap`, `rowGapCss`, `columnGapCss`, and `mainGap(is_row)` / `crossGap(is_row)`.
  - **Fixtures:** `typed flex-basis keywords and percentages (FLEX-07)`, `flex rowGap and columnGap support (FLEX-07)`, `packages/solid-zig/tests/flex-block.mjs`.

---

### Checklist: BLOCK-01 .. BLOCK-06

- [x] **BLOCK-01: Decouple Block Auto-Height from `flexDirection`.**
  - **Spec:** A container with `display: block` must calculate its natural/auto content height by stacking block children vertically, regardless of what `flexDirection` happens to be set in its style.
  - **Implementation:** In `modules/ui_core/scene.zig`, `naturalHeight` and `naturalHeightForWidth` explicitly branch on `display == .block` to dispatch directly to `layout_block.computeBlockLayout`.
  - **Fixtures:** `block natural height ignores flex direction`.

- [x] **BLOCK-02: Unified Block Layout Pass & Size Propagation.**
  - **Spec:** Block layout calculation and placement must share the exact same logic. Natural height calculation must not pre-sum uncollapsed margins or ignore child constraints.
  - **Implementation:** `modules/ui_core/layout_block.zig` introduces `BlockLayoutOutput` (`consumed_height`, `collapsible_top`, `collapsible_bottom`, `is_empty`) and `computeBlockLayout`. Used by both measurement (`naturalHeightForWidth`) and final positioning (`layoutBlock`).
  - **Fixtures:** `block sibling advances by constrained height`, `nested auto block measures child ratio before sibling placement`.

- [x] **BLOCK-03: Block Used Width & Horizontal Auto Margins.**
  - **Spec:** CSS 2.1 §10.3.3. Explicit child width is not forcibly clamped to parent width (overflow is preserved). When child width is definite, `margin: 0 auto` divides remaining space evenly between left and right auto margins; single auto margins absorb the entire remaining space.
  - **Implementation:** In `modules/ui_core/layout_block.zig`, auto margin distribution computes `remaining_space = avail_width - (border_box_width + specified_margins)`. Over-wide explicit width is allowed to overflow naturally.
  - **Fixtures:** `block horizontal auto margins distribute space`, `over-wide block child is not clamped to parent width`.

- [x] **BLOCK-04: Multi-Margin Strut (CollapsibleMarginSet).**
  - **Spec:** Collapsing adjoining margins requires tracking the maximum positive margin and minimum negative margin across all margins in the collapse strut. The resolved margin is `positive + negative`. Pairwise scalar collapsing loses extremes across chains of empty blocks.
  - **Implementation:** In `modules/ui_core/layout_block.zig`, `CollapsibleMarginSet` struct tracks `positive: f32` and `negative: f32`, with methods `collapseWithMargin`, `collapseWithSet`, and `resolve`.
  - **Fixtures:** `C-COLLAPSE-SET: multi-margin strut preserves positive and negative extrema (BLOCK-04)`.

- [x] **BLOCK-05: Parent-Child Margin Collapsing Boundaries.**
  - **Spec:** If a block container has no top padding and no top border, its first in-flow child's top margin collapses with the parent's top margin. If it has no bottom padding, bottom border, and auto height, the last in-flow child's bottom margin collapses with the parent's bottom margin. Empty blocks collapse their own top and bottom margins together.
  - **Implementation:** In `computeBlockLayout`, `collapsible_top` and `collapsible_bottom` propagate across parent-child boundaries when padding and border are zero.
  - **Fixtures:** `parent and child top and bottom margin collapsing (BLOCK-05)`, `empty block margins collapse through`.

- [x] **BLOCK-06: Accurate Block Formatting Context (BFC) Triggers.**
  - **Spec:** `overflow: clip` does NOT establish an independent BFC; child margins collapse through it into the parent strut. Formats that DO establish BFC: `flow-root`, `overflow: hidden`, `overflow: scroll`, `overflow: auto`.
  - **Implementation:** `establishesBfc(n)` in `modules/ui_core/layout_block.zig` checks `display == .flow_root` or `overflow == .hidden / .scroll / .auto`. `overflow == .clip` and `overflow == .visible` do not establish a BFC.
  - **Fixtures:** `C-CLIP-BFC: overflow:clip does not establish BFC while hidden does (BLOCK-06)`.

---

## Files and Symbols Changed

| File | Changes / Symbols Added or Updated |
| --- | --- |
| `modules/ui_core/style.zig` | Added `rowGap`, `columnGap`, `rowGapCss`, `columnGapCss` to `Style`. |
| `modules/ui_core/scene.zig` | Added `mainGap(is_row)`, `crossGap(is_row)` on `Node`. Updated `resolveStyle` to parse `rowGap`/`columnGap`. Updated `prepareChildren` to parse typed `flexBasisCss` (`content`, `auto`, `max-content`, `min-content`, percentages, lengths). Decoupled `naturalHeight` and `naturalHeightForWidth` for `display: block` to use `layout_block.computeBlockLayout`. |
| `modules/ui_core/layout_block.zig` | Added `CollapsibleMarginSet` (`positive`, `negative`, `collapseWithMargin`, `collapseWithSet`, `resolve`). Added `establishesBfc(n)`. Added `BlockLayoutOutput` and `computeBlockLayout`. Implemented horizontal auto margin distribution (`margin: 0 auto`, left/right auto). Implemented empty box margin pass-through and parent-child margin boundary collapse. |
| `modules/ui_core/layout_flex.zig` | Implemented W3C Flexbox §9.7 / Taffy iterative flexible length resolution loop (`resolveFlexibleLengths`) with fractional factor scaling (`FLEX-01`), separate raw bases vs hypothetical sizes (`FLEX-02`), and min/max freezing loop. Implemented typed `flex-basis` resolution (`resolveMainBasis`). Decoupled `minContentWidth` and `maxContentWidth` (`FLEX-03`). Fixed single-line nowrap definite cross sizing (`FLEX-04`) and `wrap-reverse` coordinate inversion. Added post-flex auto cross-axis remeasurement (`FLEX-05`). Preserved document order in `scene.items` emissions (`FLEX-06`). Added gap support (`FLEX-07`). |
| `packages/solid-zig/src/native.js` | Added `flex` shorthand parser, `flexBasis` CSS value support, `flexFlow` expansion, multi-value `gap` expansion into `rowGap` and `columnGap`. |
| `packages/solid-zig/src/native.d.ts` | Added `flexFlow`, `rowGap`, `columnGap`, and typed `gap?: NativeLength`. |
| `modules/ui_core/tests.zig` | Added 11 new comprehensive layout regression tests covering FLEX-01..07 and BLOCK-01..06. |
| `packages/solid-zig/tests/flex-block.mjs` | Added JS bridge test suite verifying flex shorthand parsing, gap expansion, flexBasis preservation, and block auto margins. |

---

## Verification Results

### 1. Zig Native Unit Tests
```powershell
zig test modules/ui_core/root.zig
```
**Result:** 65/65 tests passed (100% pass rate).

### 2. Node JS Bridge Tests
```powershell
node packages/solid-zig/tests/flex-block.mjs
node packages/solid-zig/tests/box-style.mjs
```
**Result:** All bridge assertions passed.

### 3. Solid Probe Test Suites
```powershell
npm run test:features
npm run test:bridge
npm run test:refresh
npm run test:tree
```
**Result:** All probe tests passed without regressions.
