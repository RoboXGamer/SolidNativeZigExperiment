# Native Solid/Zig CSS compatibility audit

Audit date: 2026-11-11. Audited application commit: **`8873c31`**. This report includes defects in that latest continuation as well as limitations in earlier drafts. It is an assessment of the current implementation, not an attribution of defects to a contributor.

**Conclusion:** the project has a genuine retained native renderer, substantial custom flex layout, a partial block algorithm, injected text measurement, and upstream Solid 2 reactivity. It does **not** yet have a CSS-compatible box/sizing foundation, a complete flex/block formatting implementation, a text layout engine, or a semantic select control. Calling those subsystems “implemented” must currently mean “a useful subset exists,” not “CSS behavior is complete.”

No application build, test, benchmark, browser comparison, or native execution was performed for this audit, respecting the prior testing pause. Documentation scripts fetched compatibility metadata and generated inventories/checklists only. Findings marked **D** follow directly from source branches or arithmetic; **R** are integration risks needing reproduction; **M** are missing functionality. D does not mean a desktop reproduction has been executed. Percentages below are explicitly **source-review planning estimates**, not measured compatibility.

## 1. What “100% through Baseline 2024” means here

The frozen target is **all CSS-related WebDX compatibility keys that reached Baseline newly available on or before 2024-12-31**, including older CSS. It is not just the features first added during 2024, and not just the features marked widely available in 2024. Baseline describes availability across a core set of browsers, not Chrome alone. See [MDN's definition](https://developer.mozilla.org/en-US/docs/Glossary/Baseline/Compatibility) and [the 2024 cohort](https://web.dev/baseline/2024).

Chrome's end-of-2024 stable release is treated separately as **Chrome 131**. The official [131 release notes](https://developer.chrome.com/release-notes/131) give November 12, 2024; [132](https://developer.chrome.com/release-notes/132) belongs to January 2025. Features shipped by Chrome but not yet interoperable in 2024 are an additional target, not silently redefined as Baseline. Experimental, flagged, prefixed, removed, and platform-dependent behavior need explicit historical scope decisions.

The pinned `web-features@3.45.0` dataset produces:

| Inventory | Result | Meaning |
| --- | ---: | --- |
| Cumulative CSS feature groups through the cutoff | 288 | Groups with one or more eligible `css.*` compatibility keys |
| Eligible individual CSS compatibility keys | 2,293 | Includes values, selectors, at-rules and CSS hooks into HTML/SVG/MathML |
| Groups with a partial native analogue in this source | 22 | Some related style/layout behavior exists; **not complete support** |
| Groups with no native feature analogue identified | 266 | Named individually in the inventory |
| Additional groups with Chrome <=131 keys outside that Baseline set | 106 | Discovery supplement; may overlap group names but contains different keys |
| Measured CSS/WPT conformance | **Unknown** | No applicable browser/WPT comparison has been run |

The 22/288 figure is a **feature-surface presence count**, not 7.6% CSS correctness. Group sizes differ substantially and overlap. No feature group is certified fully conformant by this audit. The catalog includes deprecated records where WebDX retains historical CSS keys; it is a reviewable extraction, not a claim that every such key should become a modern product requirement. The JSON preserves per-key dates: a group with later additions does not pull those additions into the 2024 target.

For “100%” to become a meaningful acceptance claim, freeze an applicable conformance-test manifest too: exact WPT commit/test IDs, feature-to-test mapping, Chrome oracle version/platform/font/DPI setup, declared exclusions, and pass/fail results. A percentage without that denominator is not a browser compatibility measurement. The WebDX supplement is not a complete historical Chromium/BCD export.

Artifacts:

- [Every Baseline feature name and source status](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/baseline-feature-inventory.md).
- [Baseline per-key JSON, dates, specs and source checksum](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/baseline-2024-css.json).
- [Separate Chrome 131 discovery supplement](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/chrome-131-css-supplement.json).
- [Machine-readable assessment](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/assessment.json).

## 2. Percentage assessment with an explicit denominator

Each subsystem has **ten named obligations**. Each gets `0` for a missing foundation, `0.5` for partial implementation, or `1` for a narrowly implemented capability. The score is `100 × points / 10`. A narrow `1` does not certify surrounding CSS interactions. These are coarse planning judgments; they do not measure code coverage, schedule completion, correctness probability, or WPT results. Do not average these categories into “overall CSS compatibility.”

| Subsystem | Planning coverage | What exists | Main unfinished part |
| --- | ---: | --- | --- |
| Box model and sizing | **30%** | Numeric sizes/edges, frame helpers, clamps | Typed lengths, zero/auto, single margin ownership, consistent used sizes |
| Flex layout | **45%** | Order/axes, line collection, distribution, alignment branches | Spec flex bases/free-space/freezing, cross remeasurement, intrinsic sizing |
| Block layout | **25%** | Vertical flow, partial width adjustment, margin-pair collapsing | Correct used-height pass, collapse sets, BFC/IFC, floats/replaced content |
| Text metrics and typography | **25%** | Real backend width callback, intrinsic word/run helpers | Shaping, actual font metrics, line boxes/wrapping, Unicode/font selection |
| Grid layout | **15%** | Row-major fixed/fr columns and estimated row heights | Track sizing, rows, placement/spans, auto-flow, alignment/subgrid |
| Box painting and colors | **30%** | Solid rectangles, basic borders/radii/outline/shadow approximation | CSS colors, accurate border geometry, per-corner clips, blur/layers |
| Overflow and scrolling | **20%** | Rectangular clips, clip-aware hits, vertical wheel offsets | Full overflow propagation, scroll APIs/chaining/gutters and per-axis semantics |
| Single-line input/focus | **30%** | Codepoint editing, keyboard selection/clipboard, basic focus | IME/graphemes, pointer editing, semantics, accessibility/history |
| Select/option control | **0%** | Demo-specific in-flow button dropdown only | Actual select/option model, keyboard/popup/value/event/accessibility contract |
| CSS language/style resolution | **0%** | A small inline object projection | Parser, selectors/cascade/computed values/variables/pseudos/at-rules |
| Positioning/stacking | **5%** | Custom normal-flow placement | Relative/absolute/fixed/sticky, containing blocks, stacking contexts |
| Responsive/conditional styling | **0%** | Window resize relayout only | Media/container queries, responsive/relative units and dependency tracking |
| Motion/transforms/effects | **0%** | Timer-based JS animation callbacks only | CSS transitions/animations/transforms/filter/compositor semantics |
| Other CSS formatting families | **0%** | No complete implementation | Tables, lists/counters, multicolumn, ruby, SVG/MathML CSS, printing/containment |
| Solid native integration | **60%** | Actual client APIs, universal host, async/HMR wiring | Native publication/marker semantics and broad end-to-end evidence |
| Bridge/event loop/dev host | **55%** | QuickJS, jobs, timers, retained commits and custom HMR host | Transaction boundaries, recovery, incremental work, public packaging/platforms |
| Accessibility/semantic UI | **0%** | Internal focus ID only | Accessible tree, roles/names/values, Windows UI Automation, label relationships |

The complete scored obligations and justifications are in [coverage-checklist.md](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/coverage-checklist.md). [coverage.html](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/coverage.html) visualizes the same data; it is not a separate set of estimates.

## 3. Work already present, and what the history actually establishes

| Commit | Actual contribution | What it does not establish |
| --- | --- | --- |
| `7256960` | Saved Raylib window baseline | CSS/Solid behavior |
| `8d11f37` | Solid/QuickJS counter experiment | General native UI semantics |
| `7e59eec` | Solid Refresh integration | Full application module/ESM support |
| `02594f4` | `ui_core`, `solid_bridge`, JS package, retained delta tree, timer/job APIs, application module host and primitive probes | Algorithm completeness or all primitives proven in native execution |
| `63f2e8d` | Box styles, partial block/grid paths, painting, States/City demo and broad CSS reference | Real select/option semantics or full CSS box sizing |
| `d233191` | Substantial flex implementation, including alignment/wrapping/distribution | Spec-complete flexible-length and intrinsic algorithms |
| `5c982cf` | Split geometry/style/scene/block/flex/text modules, real text-width seam, tests and regression fixes | A shaping/inline formatting engine; it also removed the C/QuickJS smoke harness |
| `8873c31` | Build helpers, validation, scroll/edit/event wake code, HMR extensions, types and one-command dev | Tested completion; still contains defects identified below |

The layout split, box/block/flex work, text callback, incremental bridge, module host and real Solid JSX all predate the latest continuation. They are real work and should be retained. They are not blank subsystems requiring a new design from scratch.

The core is backend independent, the QuickJS bridge is separate, and the app keeps the conventional `src/main.zig -> src/root.zig -> src/windows.zig` path. The present architecture is compatible with continued native development. Allocation choice alone does not establish speed or CSS correctness.

## 4. Concrete source findings

Priority `P1` means fix before expanding claims or relying on CSS-like behavior in app screens. `P2` means a bounded compatibility gap or an important integration issue. `P3` is a lower-priority contract/tooling limitation. These are technical priorities, not an estimate of implementation effort.

### 4.1 Box model and value representation

| ID | Type / priority | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| BOX-01 | D / P1 | **Zero, auto and indefinite are conflated.** `width: 0`, `height: 0`, `maxWidth: 0`, `minWidth: 0` are treated as missing by `> 0` checks. In flex, explicit `minWidth: 0` cannot opt out of the content-based minimum. | [style.zig:15](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/style.zig:15), [scene.zig:173](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:173), [layout_flex.zig:133](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:133) |
| BOX-02 | D / P1 | **Explicit zero longhands cannot override shorthand values.** Padding/border choose a side only if positive; margin chooses it only if nonzero. Buttons/inputs add 10px to shorthand padding even when the author supplied padding. Example: padding 20 plus paddingLeft 0 still yields a 20px left inset. | [scene.zig:29](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:29) |
| BOX-03 | D / P1 | **A real -1px margin becomes `auto`.** One float value encodes both legal negative length and keyword. Negative margin handling is therefore not generally correct. | [scene.zig:16](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:16), [scene.zig:63](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:63) |
| BOX-04 | D / P1 | **Margins are counted inside their own box.** Parent flex placement accounts for child margins, then the child's layout subtracts its own margins from inner space and adds them again to content origins. Margins belong outside the border box. Nested containers shift children and lose content space. | [scene.zig:184](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:184), [layout_flex.zig:378](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:378), [layout_block.zig:51](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:51) |
| BOX-05 | D / P1 | **No unified content-/border-box used-size contract.** Block width adds padding/border for content-box; flex basis/width and explicit heights do not consistently do so. The borderBox helper also outsets borders despite painting/layout treating supplied bounds as the box rectangle. | [layout_block.zig:38](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:38), [layout_flex.zig:122](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:122), [scene.zig:74](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:74) |
| BOX-06 | D / P1 | **Clamps are late and inconsistent.** Scene applies min then max, so max can defeat a larger min; flex computes max as at least min. Block/grid parents advance using a pre-clamp height, so a later enlarged child may overlap its sibling. | [scene.zig:173](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:173), [layout_flex.zig:274](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:274), [layout_block.zig:84](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:84) |
| BOX-07 | D / P1 | **Aspect ratio is a zero-height fallback.** It does not participate in preferred/min/max size transfer, width-from-height sizing or replaced-element rules; normal stretch/natural-height paths can prevent it from applying at all. | [scene.zig:177](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:177) |
| BOX-08 | D/M / P1 | **Display dispatch is not CSS box generation.** `none`, `contents`, inline/inline-flex, flow-root, table/list modes are absent. An unsupported display string falls through to flex; grid columns trigger grid regardless of display. Flex-by-default custom elements are an intentional API convention, but differ from HTML/CSS defaults. | [scene.zig:189](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:189), [scene.zig:217](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:217), [native.js:28](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:28) |
| BOX-09 | D/M / P1 | **CSS values are inconsistently discarded or misread.** String widths such as `"100px"` become zero/auto. Spacing uses parseFloat, so `"10%"` becomes 10 pixels and `"2rem"` becomes 2, without unit resolution or invalid-value recovery. NaN/infinite numeric styles have no shared validation contract. | [native.js:33](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:33), [native.js:112](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:112) |

The reference [CSS box-sizing definition](https://developer.mozilla.org/en-US/docs/Web/CSS/box-sizing) requires a consistent relationship among content dimensions, padding and borders. The present positive-number projection cannot represent that contract across all layout modes.

### 4.2 Flex layout

| ID | Type / priority | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| FLEX-01 | D / P1 | **Factors whose sum is below 1 consume the full free space.** A single empty item with basis 0, grow 0.25 and min 0 in a 100px row gets 100px here; the flex algorithm preserves the unused fraction and gives 25px. Partial shrink factors have the corresponding problem. | [layout_flex.zig:189](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:189) |
| FLEX-02 | D / P1 | **Raw flex bases, hypothetical sizes and target sizes are conflated.** Base is clamped to min/max before flexible length resolution. Distribution adds adjustments to current sizes and uses a simplified freeze rule, rather than separate raw bases and total min/max violations. This changes constrained item ratios. | [layout_flex.zig:175](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:175), [layout_flex.zig:275](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:275) |
| FLEX-03 | D / P1 | **Intrinsic contributions are approximations.** Recursion uses flexDirection even for block/grid content, omits child outer contributions in several paths, and computes a single-run word minimum. CSS automatic minima also depend on specified/transferred size and scroll-container rules. | [layout_flex.zig:65](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:65), [layout_flex.zig:133](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:133) |
| FLEX-04 | D / P1 | **Single-line cross sizing depends on align-content.** With nowrap, line size should use the definite container cross size independently of align-content. Here only align-content stretch fills it. A wrap-reverse container with only one line also bypasses reversal. | [layout_flex.zig:320](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:320), [layout_flex.zig:372](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:372) |
| FLEX-05 | D/M / P1 | **Cross sizes are computed before main-axis flexing and never remeasured.** Wrapped/nested content cannot contribute its height after its final width is known; auto container size does not emerge from final lines. | [layout_flex.zig:277](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:277), [layout_flex.zig:308](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:308), [layout_flex.zig:402](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:402) |
| FLEX-06 | D / P2 | **Visual order controls Tab order.** Layout emits items in CSS order, then native focus iterates scene.items. CSS visual reordering must not automatically replace semantic/document focus order. | [layout_flex.zig:243](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:243), [windows.zig:271](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:271) |
| FLEX-07 | D/M / P2 | **Flex value grammar is partial.** `flex: "1 20px"` reads `20px` as a shrink factor, then falls back to shrink 1 and basis 0. A string `flexBasis: "20px"` is ignored. flex-flow and separate row/column/percentage gaps are absent. | [native.js:53](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:53) |

Taffy's `resolve_flexible_lengths` separately tracks basis/hypothetical/target sizes, initial free space, scaled inner shrink factors and total violations. These are existing Flexbox Level 1 requirements, not post-2024 enhancements. Compare [the 2018 algorithm](https://www.w3.org/TR/2018/CR-css-flexbox-1-20181119/#resolve-flexible-lengths) and [local Taffy flexbox.rs:1805](C:/Users/A5IN/Coding/reference/taffy/src/compute/flexbox.rs:1805).

The 64-child truncation and zero-shrink coercion were addressed in `8873c31`; they should not be reported as still present. Their replacements have not been validated by this audit.

### 4.3 Block formatting

| ID | Type / priority | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| BLOCK-01 | D / P1 | **Auto height uses flexDirection even for display:block.** A block with two 10px block children can report only 10px natural height when its flexDirection is row, while block layout stacks them to 20px. This is hidden in the normal bridge defaults but exposed by legitimate explicit styles and direct core use. | [scene.zig:154](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:154) |
| BLOCK-02 | D / P1 | **There is no final block output pass.** naturalHeight pre-sums uncollapsed child margins, ignores actual final constrained sizes and does not return consumed height/collapsible margins/baselines to the parent. Auto sizing and placement can disagree. | [scene.zig:136](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:136), [layout_block.zig:43](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:43) |
| BLOCK-03 | D / P1 | **The block used-width equation is incomplete.** Explicit width is forcibly capped at the parent's inner width, even when CSS should overflow. Auto width does not properly deduct child margins; horizontal auto margins are resolved to zero instead of centering. | [layout_block.zig:38](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:38) |
| BLOCK-04 | D / P1 | **Pairwise collapsed scalars lose a multi-margin strut.** Collapsing +20, -10, +15 sequentially produces 15 with collapsePair; a collapsed set preserves max positive 20 and min negative -10, resolving to 10. Chains of empty blocks need that set, not repeated scalar reduction. | [layout_block.zig:13](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:13), [layout_block.zig:63](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:63) |
| BLOCK-05 | D/M / P1 | **Parent/first-child collapse updates are too late/local.** content_top is captured before parent_top_margin_used is updated. A child's escaping top margin is not propagated as parent output; parent/last-child bottom collapse is absent. Empty eligibility also does not encode all min-height/formatting constraints. | [layout_block.zig:47](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:47), [layout_block.zig:50](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:50), [layout_block.zig:71](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:71) |
| BLOCK-06 | D/M / P2 | **BFC detection treats overflow:clip as a BFC.** clip does not create one; other real BFC triggers are missing. No float context, clearance, flow-root behavior or inline formatting context exists. | [layout_block.zig:27](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_block.zig:27) |

The [margin-collapse rules](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_box_model/Mastering_margin_collapsing) and [overflow distinction](https://developer.mozilla.org/en-US/docs/Web/CSS/overflow) are the relevant web behavior. Taffy's [CollapsibleMarginSet](C:/Users/A5IN/Coding/reference/taffy/src/tree/layout.rs:146) stores positive and negative components; its block output propagates collapse information. A BFC implementation and an IFC implementation are different pieces of work.

### 4.4 Grid, text and painting

| ID | Type / priority | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| GRID-01 | D/M / P2 | **Column packing is not CSS Grid.** There is no explicit row model, placement/spans/areas, dense auto-flow, minmax/repeat, intrinsic track sizing, grid item alignment or subgrid. `display:grid` alone falls through to flex unless columns are supplied. | [scene.zig:189](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:189) |
| GRID-02 | D / P2 | **Track/row accounting is naive.** fr simply divides leftover width; fixed tracks and child minimums can overflow without a track-sizing feedback pass. Row advance uses naturalHeight before final clamps; own child width/margins/alignment do not follow grid rules. | [scene.zig:195](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:195) |
| TEXT-01 | D/M / P1 | **Width measurement is real, ascent is not.** Raylib supplies width, but height is assigned font_size and ascent is assigned 0.8em. Flex baselines return zero for any non-text child. Container/button baselines and font ascent/descent/leading are not measured. | [windows.zig:45](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:45), [layout_flex.zig:157](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/layout_flex.zig:157) |
| TEXT-02 | D/R / P2 | **Measure/paint can disagree.** Measurement rounds font size; painting truncates it. Long runs are measured in chunks then painted as one run, so inter-chunk spacing/context can differ. Scissor rectangles independently truncate coordinates and sizes instead of using consistent rounded edges. | [windows.zig:33](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:33), [windows.zig:64](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:64), [windows.zig:101](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:101) |
| TEXT-03 | D/M / P1 | **Intrinsic text sizing is not Unicode/CSS text layout.** Min-content splits ASCII whitespace; max-content splits newline but naturalHeight still reports one line. Fallback estimates count UTF-8 bytes, not glyphs/codepoints. No shaping, fallback fonts, bidi or Unicode breaking exists. | [text.zig:75](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/text.zig:75), [text.zig:133](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/text.zig:133), [scene.zig:139](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:139) |
| TEXT-04 | D/M / P1 | **wrap() is disconnected and insufficient for painting.** It returns only count/widest width, not positioned runs/ranges. It tokenizes away hard line breaks and whitespace; even an all-whitespace run can be counted as a line without content. Neither layout nor paint uses it. | [text.zig:101](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/text.zig:101), [windows.zig:102](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:102) |
| PAINT-01 | D/M / P2 | **Color syntax is six-digit hex only.** Short/alpha hex, named/system colors, transparent/currentColor, rgb/hsl and modern color spaces/functions are unsupported; fallback colors can hide the rejection. | [windows.zig:17](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:17) |
| PAINT-02 | D / P2 | **Borders do not follow CSS edge geometry.** DrawLineEx strokes are centered on the box edge, consuming both inside and outside space. The uniform rounded path ignores per-side colors when widths happen to match. Border styles and joins are missing. | [windows.zig:87](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:87) |
| PAINT-03 | D/M / P2 | **Per-corner radius fields are mostly transport-only.** Top-left or uniform radius is used for every corner; other corner fields do not affect painting. Elliptical radii and matching clip/hit geometry are absent. | [native.js:142](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:142), [windows.zig:59](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:59) |
| PAINT-04 | D/M / P2 | **boxShadow is a custom five-token approximation.** Blur is explicitly discarded. CSS px tokens fail Zig parseFloat, and normal optional terms, inset, multiple shadows and color syntax are not parsed. | [windows.zig:66](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:66) |

Taffy's leaf measurement callback receives known and available dimensions, allowing constrained measurement to feed layout. Our callback only receives text and font size. Taffy itself does **not** supply a full shaping/rendering system; using its algorithms as reference does not complete typography.

### 4.5 Scrolling, controls, demo and Solid integration

| ID | Type / priority | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| SCROLL-01 | D / P2 | **Scrollable extent ignores overflowing grandchildren.** Only direct child bottoms are checked. A short direct child with visible overflow below it cannot expand the ancestor's scroll range. Negative/top/left overflow, horizontal extent and scrollbar geometry are also unmodeled. | [scene.zig:253](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:253) |
| SCROLL-02 | D/M / P2 | **Nested wheel scrolling has no chaining.** The deepest scroll/auto node always wins even with no overflow or at an edge; the outer viewport does not consume unused delta. No scrollIntoView, focus visibility, independent axes or snap behavior exists. | [scene.zig:271](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/scene.zig:271), [windows.zig:245](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:245) |
| INPUT-01 | M / P2 | **Input is a single-line custom editor, not HTML input.** Codepoint navigation can split a grapheme sequence; IME, bidi selection, pointer caret/dragging, undo, defaultValue, input types, validation, selection APIs and form semantics are missing. Input value is sent through a NUL-terminated C string, so embedded NUL is not a lossless bridge contract. | [text_edit.zig:24](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/text_edit.zig:24), [windows.zig:134](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:134), [quickjs_bridge.c:110](C:/Users/A5IN/Coding/learning/zig/draft1/modules/solid_bridge/quickjs_bridge.c:110) |
| INPUT-02 | D/M / P2 | **Clickable and focusable are conflated.** Any click-handler node enters Tab order; a button without a click handler does not. No tabindex or focus/blur API, label/id association, Space activation or semantic focus order. Dynamically disabled focus is not cleared unless the node disappears. | [native.js:97](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:97), [windows.zig:265](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:265), [windows.zig:318](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:318) |
| SELECT-01 | M / P1 | **No select/option control exists.** JSX types omit select/option/optgroup; only input.value is transported; no selection model/change event/popup/keyboard/a11y path exists. Creating an arbitrary `select` node would merely create a generic container. The demo's Dropdown expands buttons in normal flow. | [native.d.ts:89](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.d.ts:89), [native.js:98](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:98), [states.jsx:24](C:/Users/A5IN/Coding/learning/zig/draft1/ui/states.jsx:24) |
| DEMO-01 | D/R / P2 | **Async city results have no owner/key guard.** Detached async functions write when they finish without checking selectedState or disposal. With variable real-network latency an older request can overwrite a newer choice; the fixed-delay fixture does not demonstrate that race. Old city selection remains visible during a state change, so the displayed state/city pair can temporarily be invalid even in the fixture. | [states.jsx:69](C:/Users/A5IN/Coding/learning/zig/draft1/ui/states.jsx:69) |
| SOLID-01 | D/R / P1 | **Renderer markers leak into layout.** Upstream universal defaults createSentinel to an empty text node. The adapter supplies no non-layout marker and snapshot serializes every child. Empty conditional regions can therefore count as flex items/gaps/order slots. Existing tree probes filter by label type, hiding that geometry issue. The exact compiled demo manifestation still needs a native comparison. | [renderer.js:6](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/renderer.js:6), [native.js:154](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:154), [universal.ts:121](C:/Users/A5IN/Coding/reference/upstream-reference/solid2/packages/universal/src/universal.ts:121) |

The select target is the conventional 2024 select/listbox behavior described by [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/select), not newer customizable-select features added after the cutoff. A native select does not require a WebView: implement a typed native control contract and popup/focus/selection behavior in this renderer. That is additional work, not something Solid or Taffy supplies automatically.

### 4.6 Bridge, scheduling, HMR and library boundaries

| ID | Type / priority | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| HOST-01 | D/R / P1 | **Publication/acknowledgement needs a stronger transaction.** Native acknowledges after Tree.apply but before layout succeeds. Also ui_eval_string snapshots before draining jobs; acknowledge drains more jobs. A job-heavy transition can mutate JS after the captured tree, leaving the window waiting without an explicit renderer-dirty wake if all jobs finish. The ordering risk needs an end-to-end reproduction; it is not an upstream Solid primitive defect. | [windows.zig:187](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:187), [quickjs_bridge.c:96](C:/Users/A5IN/Coding/learning/zig/draft1/modules/solid_bridge/quickjs_bridge.c:96) |
| HOST-02 | D/R / P2 | **Wake failure paths are not observable/recoverable.** SetWaitableTimer return value is ignored and a later worker wait failure just exits. The app can continue believing event-driven deadlines will wake it. Non-Windows uses 60Hz polling; there is no matching native timer/watcher implementation there. rAF is a 16ms timeout, not synchronized to presentation. | [event_wakeup.c:29](C:/Users/A5IN/Coding/learning/zig/draft1/src/event_wakeup.c:29), [quickjs_bridge.c:74](C:/Users/A5IN/Coding/learning/zig/draft1/modules/solid_bridge/quickjs_bridge.c:74) |
| HOST-03 | D / P2 | **Incremental transport is not incremental layout.** Every synchronization builds/traverses a full JS snapshot and serializes signatures. A changed patch clones/validates the complete native map and materializes/layouts the entire tree. Intrinsic traversals and scroll ancestor/descendant scans can repeat work; no benchmark or per-node measurement cache establishes large-app performance. | [native.js:178](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/native.js:178), [tree.zig:62](C:/Users/A5IN/Coding/learning/zig/draft1/modules/ui_core/tree.zig:62), [windows.zig:300](C:/Users/A5IN/Coding/learning/zig/draft1/src/windows.zig:300) |
| HOST-04 | M / P3 | **Module separation is real; public distribution is incomplete.** Helpers/standalone build files exist, but no separate Zig package manifests/releases, no public JS workspace dependency, JS package remains private, and the bridge hardcodes a sample HMR file plus one process-global runtime. No public license/compatibility/versioning/release validation contract has been completed. | [solid_bridge/build.zig:29](C:/Users/A5IN/Coding/learning/zig/draft1/modules/solid_bridge/build.zig:29), [solid-zig/package.json:4](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/package.json:4), [quickjs_bridge.c:147](C:/Users/A5IN/Coding/learning/zig/draft1/modules/solid_bridge/quickjs_bridge.c:147) |
| HMR-01 | D/R / P2 | **Runtime update failures are not transactional.** Definitions and disposals mutate the live graph before new modules execute. An execution/accept callback error can leave partially replaced state; the same-source retry is not a guaranteed recovery. Full invalidation remounts everything and therefore loses application state. | [module-runtime.js:87](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/module-runtime.js:87) |
| HMR-02 | D/M / P2 | **This is a custom CommonJS-based host, not the complete Vite browser client.** Static/re-export/literal dynamic paths exist, but computed imports, top-level await, full cyclic ESM/live-binding behavior, arbitrary CSS/DOM packages, hot.send/custom events and framework-host hot updates are unsupported or incomplete. Native framework modules are externals and require restart. | [dev.mjs:40](C:/Users/A5IN/Coding/learning/zig/draft1/tools/dev.mjs:40), [module-runtime.js:25](C:/Users/A5IN/Coding/learning/zig/draft1/packages/solid-zig/src/module-runtime.js:25) |

The retained Tree.apply implementation stages allocations and validates references/cycles/shared nodes before replacing the tree; this is useful existing behavior. Its all-or-nothing tree update should not be confused with atomic JavaScript execution, successful layout/paint, or an upstream Solid publication frame.

## 5. Solid 2: supplied API versus native proof

All **36 requested names map to upstream client APIs** at the pinned rc.21. We should not reimplement those primitives in Zig or replace them with local shims. The local reference and installed package both identify that release. The universal renderer is the intended seam.

| Group | Names supplied | Existing probe shape | Missing native evidence |
| --- | --- | --- | --- |
| Reactive primitives | createDeferred, createEffect, createMemo, createOptimistic, createSignal, flush, from, isPending, latest, untrack | Synthetic signals/memos/effects, initial deferred, settled reads, one emitted source value | Deferred invalidation timing, pending/held frames, source unsubscribe, errors/cancellation and native wake behavior |
| Stores | createOptimisticStore, createProjection, createStore, merge, omit, reconcile | Single-root mutation/projection/reconcile and optimistic rollback | Nested components, keyed retained identity, async projections, replaced/unmounted ownership and actual native property updates |
| Lifecycle/actions | action, affects, onFlush, onSettled, refresh, until | One successful generator action and synthetic lifecycle checks | Failed/superseded/concurrent actions, cancellation, settled ownership and external/native event interactions |
| Components/context | children, createContext, createUniqueId, lazy, lazyModule, useContext | Flattening, default context, different IDs and resolved/preloaded in-memory lazy result | Context provider hierarchy, reactive values/disposal, label/id native semantics, actual Vite import failures/retries/HMR |
| JSX flow | Errored, For, Loading, Repeat, Reveal, Show, Switch, Match | Text outputs for simple branches, For/Show reorder/hide; synchronous ready Loading/Reveal | Held async publication, Reveal ordering/nesting, Errored reset/rejection, marker geometry, focus/scroll retention |

`createUniqueId` returning a unique string does not implement native `id`, `<label for>`, `aria-labelledby` or an accessibility tree. Having `Loading` exported does not prove native frame publication is correct under suspense. The current demo uses explicit loading signals and detached promises, rather than demonstrating all of those Solid async semantics.

Reference: [Solid universal renderer](C:/Users/A5IN/Coding/reference/upstream-reference/solid2/packages/universal/src/universal.ts:121), [Loading/Reveal](C:/Users/A5IN/Coding/reference/upstream-reference/solid2/packages/solid/src/client/flow.ts:442), [lazy/lazyModule](C:/Users/A5IN/Coding/reference/upstream-reference/solid2/packages/solid/src/client/component.ts:144), [client hydration wrappers](C:/Users/A5IN/Coding/reference/upstream-reference/solid2/packages/solid/src/client/hydration.ts:15), [API exports](C:/Users/A5IN/Coding/reference/upstream-reference/solid2/packages/solid/src/index.ts:1).

## 6. What the existing tests can miss

Tests were read, not executed. The current core suite has 18 tests in tests.zig, plus geometry/text helper tests. There are useful regressions here, but they do not form a CSS conformance suite.

- The box test checks that x is positive and width is <=300; it does not assert the box-model equation or exact padding/margin/border positions.
- The ratio test checks height >0, not width/height == the requested ratio. It can pass without correct aspect-ratio sizing.
- The sibling margin test checks a lower bound, not the exact collapsed gap. An over-large gap can pass.
- The “margin auto” helper test supplies no actual auto margins. Other flex tests do cover simple centering, but that test itself proves default zeros only.
- The overflow test checks parent_id, not the painted clip, overflow extent, hit region, nested scroll behavior or focus visibility.
- The shrink test checks only a minimum width bound; it does not validate distribution among constrained peers.
- The tree probe filters children to labels, so marker nodes affecting layout are invisible to its assertion.
- The primitive probe mainly checks API existence and synthetic settled outputs. Context-provider behavior, real async Loading/Reveal behavior and native pixel/layout/input results are not checked.
- Refresh probe uses a small in-memory hot object. It is not a real Vite -> file watcher -> QuickJS -> scene/paint update path test.
- No current fault-injection coverage establishes tree/layout failure ownership, timer worker failure, HMR runtime-error recovery or memory behavior over long edit/update runs.
- The old C QuickJS smoke harness was removed in `5c982cf`. Existing Node probes do not replace execution in QuickJS with its actual host bootstrap.
- There are no `<select>` tests because there is no select implementation.

The tracked dev-check output records successful startup/shutdown of an earlier Raylib run and its default 224-glyph font. It is historical evidence, not evidence that the current layout algorithm or new event loop is correct.

## 7. Named backlog toward the stated compatibility target

The catalog names every extracted Baseline group; this section groups the engineering work so it can be implemented coherently.

1. **Style/value foundation:** typed Length/Percentage/Auto/Intrinsic/Calc values; explicit unset/zero; validation; style grammar; property metadata; shorthand expansion; inherited/computed/used values; logical-to-physical mapping; viewport/font/containing-block dependencies.
2. **Box tree and sizing:** content/padding/border/margin boxes; display:none/contents/inline/inline-block/block/flex/grid; anonymous boxes; CSS defaults versus native custom-element defaults; preferred/min/max size transfer; aspect ratios; replaced-element intrinsic sizes; rounding and device scale.
3. **Block and inline formatting:** used widths/heights; margin-collapse struts; BFC roots; floats/clearance/float avoidance; IFC line boxes; inline runs/inline-block baselines; shrink-to-fit; fragmentation; block align-content.
4. **Flex formatting:** separate raw bases/hypothetical/target sizes; correct freeze/violation loop; fractional factors; inner scaled shrink factors; automatic min constraints; intrinsic size passes; final-width cross measurement; single/multiple-line alignment; baselines; RTL; out-of-flow items; axis-specific gaps.
5. **Grid formatting:** explicit/implicit tracks; minmax/repeat/auto-fit/auto-fill; intrinsic/spanning contributions; row sizing; placement/lines/areas; dense auto-flow; content/item alignment; subgrid; out-of-flow children.
6. **Text/font stack:** font matching/loading/fallback, ascent/descent/leading; glyph shaping and clusters; Unicode line breaks/bidi; whitespace/text transforms; line box construction and painting; text alignment/decorations/ellipsis; font variations/features; vertical/ruby text.
7. **Position/paint/composition:** containing blocks, relative/absolute/fixed/sticky; z-index/stacking contexts; six-/short-/alpha-hex and named/system/modern color functions; backgrounds/images/gradients; border styles/joins/radii; blur shadows; opacity; clips/masks; transforms/filter/backdrop; paint/hit consistency.
8. **Overflow/scroll:** per-axis computation, propagated scrollable overflow, clip versus hidden, scrollbar/gutter layout, horizontal/programmatic scrolling, nested chaining/overscroll, focus/caret visibility, smooth/snap behavior.
9. **Controls:** semantic button/input/label/select/option/optgroup/textarea; selection/value/change/input contracts; popup manager/top-layer placement; focus manager; type-ahead; disabled/required/readOnly; forms/validation; clipboard/edit history/IME/platform text services.
10. **Style system:** parser/tokenizer; stylesheet import; selector matching/specificity; origins/importance/layers; variables/registered properties; pseudo states/elements; generated content/counters; media/container/feature queries; CSSOM and style invalidation.
11. **Animation/effects/responsiveness:** transform interpolation, transitions/keyframes/composition/easing, starting-style/discrete changes, query units/environment preferences, compositor scheduling and accessibility preferences.
12. **Other formatting/platform support:** tables/lists/multicolumn, SVG/MathML CSS, shapes, containment/content-visibility, paged media/printing, accessible semantics/Windows UI Automation, high-DPI and platform integration.
13. **Solid host robustness:** non-layout marker representation, stable focus/selection/scroll identity, renderer dirty notification/publication boundary, async error/disposal/supersession matrix, strong commit acknowledgement, HMR last-good recovery and explicit module compatibility contract.
14. **Conformance infrastructure:** frozen Baseline/Chrome/WPT manifests, differential geometry fixtures, font-controlled text fixtures, native interaction/accessibility tests, screenshots where appropriate, allocation/performance measurements after correctness.

An object-style authoring API can remain the preferred DX. It can feed this style/layout engine. However, claiming **full CSS compatibility** additionally requires the language/cascade/selector/value/formatting behavior above. If those are intentionally excluded later, rename that contract to a native CSS-like style subset instead of claiming 100% CSS.

Baseline-2024 additions must also be tracked: block align-content, scrollbar-gutter/width, text-wrap/balance and white-space-collapse, font-size-adjust, registered custom properties, relative colors/light-dark/gradient interpolation, round/mod/rem, starting-style/transition-behavior, backdrop-filter, ruby/vertical form controls, page setup, transform-box/paint-order, rect/xywh and relevant pseudo-element/state hooks. None has a complete end-to-end implementation in this project. The generated catalog supplies the exact per-key cutoff instead of treating today's MDN syntax as all valid in 2024.

## 8. Implementation order and acceptance gates

| Phase | Work | Exit condition |
| --- | --- | --- |
| A: Fix the existing foundation | BOX-01..09, SOLID-01, typed layout inputs/outputs and an explicit box contract | Zero/auto, border/content sizing, margins and marker nodes behave consistently across block/flex/grid |
| B: Do justice to existing layout | FLEX-01..07, BLOCK-01..06, final-size propagation and constrained measurement | Curated Taffy/spec cases match the chosen semantics; no silent approximation labeled complete |
| C: Deliver the requested select | Typed select/option model, popup/focus/keyboard/events; guard demo async results | State/city demo uses a reusable select, pointer and keyboard selection work, stale results cannot replace the current key |
| D: Complete text and overflow | Real font metrics, shaping/IFC/wrap, scroll extent/chaining, IME/selection | Paint and layout share runs; multilingual text, wrapped content and scrolling/input remain consistent |
| E: Broaden CSS coverage | Full grid/positioning, CSS language/style system, paint/effects/query/motion families | Each catalog feature has an implementation owner, applicable test list and explicit result |
| F: Claim compatibility | Full applicable 2024 feature/test matrix plus the separate Chrome supplement | Every included case passes the frozen oracle, with exclusions clearly listed; no coarse estimate substituted for results |

Phases are a dependency order, not a commitment that each is small. Full CSS compatibility is rendering-engine-scale work. The project can keep its Zig/native design throughout; Taffy and Solid remain references and dependency seams rather than a requirement to adopt a WebView or rewrite the project in Rust.

## 9. First differential cases to name before testing resumes

These are **specified cases, not tests run in this audit**. Expected values below assume unstyled generic boxes, numeric CSS px, no extra UA button/input padding, and an explicit size/overflow context.

| Case ID | Setup | Expected behavior / purpose |
| --- | --- | --- |
| C-ZERO | width 0; max-width 0; flex child min-width 0 | Preserve explicit zero separately from auto/unset |
| C-SIDE-ZERO | padding 20; padding-left 0; border 4; border-left-width 0 | Left padding/border remain zero |
| C-MARGIN-NEGATIVE | margin-left -1px versus auto | Distinct used values and placement |
| C-MARGIN-OWNERSHIP | 100px-wide nested box with margin-left 10, no frame | Margin shifts the box once; does not become content padding |
| C-CONTENT-BOX | width 100, height 40, padding 10, border 2 | Content-box border dimensions 124 × 64; border-box dimensions 100 × 40, subject to frame floors |
| C-MIN-MAX | min-width 100, max-width 50 | Used width respects the minimum rather than ending at 50 |
| C-PARTIAL-GROW | 100px row; empty item basis 0, grow .25, min-width 0 | Item 25px; remaining space unconsumed by flex growth |
| C-BASIS-MIN | 200px row; two grow-1, basis-0 items; minima 80 and 0 | 100/100, not 140/60 from pre-clamping the bases |
| C-NOWRAP-CROSS | Definite 100px cross size; nowrap; align-content flex-start; align-items stretch | Auto-cross items fill the single-line cross size |
| C-BLOCK-HEIGHT | display:block with two height-10 children and flexDirection row | Natural block content height is 20, not a flex row maximum |
| C-CLAMP-SIBLING | First block natural height 10, min-height 50, next sibling | Next sibling begins after the final 50px box |
| C-COLLAPSE-SET | Adjoining margins +20, -10 and +15 through an empty block | Collapsed gap 10, preserving positive/negative extrema |
| C-CLIP-BFC | Same block children under overflow:clip versus hidden | Only the appropriate overflow value establishes a BFC |
| C-NONE | display:none subtree with fixed dimensions and handlers | No layout/paint/hit/focus box from that subtree |
| C-MARKER-GAP | Conditional empty region between visible children with nonzero gap | Renderer bookkeeping adds no anonymous visual gap/item |
| C-TEXT-LINES | Two hard lines, tabs/multiple spaces, long word, combining/emoji/Indic/Arabic samples | Correct specified white-space behavior, line boxes, metrics, shaping and selection |
| C-SCROLL-DESCENDANT | Scroll viewport -> short child overflow:visible -> tall grandchild | Reach the grandchild's full scrollable bottom |
| C-NESTED-WHEEL | Nested scroll viewport at its lower edge | Defined chaining policy passes remaining delta appropriately |
| C-SELECT | Controlled options, disabled option, arrows/type-ahead/Enter/Escape/outside click | Correct value/events/focus/popup semantics with no dependence on a demo-specific button list |
| C-ASYNC-NATIVE | Loading/Reveal/Error boundaries, overlapping actions, disposal and >1024 jobs | Coherent frames, no stale native publication, deterministic cleanup/wake behavior |
| C-HMR-FAILURE | Syntax error, execution error, removed/cyclic dependency, then valid update | Last-good behavior/recovery follows an explicit contract |

Full WPT execution will need a browser-like fixture adapter or an equivalent geometry/style harness because the current host has no DOM/CSSOM. Taffy-generated layout fixtures can help earlier, but cannot validate selectors, native controls, shaping, paint, accessibility or all Chrome quirks.

## 10. Evidence, references and reproducibility

Reviewed first-party code includes every tracked Zig/C/JS/JSX/MJS implementation, types, build/config files, test/probe source, legacy Python helper, project docs and relevant historical diffs. Dependency lock metadata was checked for pins; vendor trees/generated bundles/node_modules are not claimed as exhaustively audited. The old split.py is a one-off rewrite helper for an earlier root.zig shape, not part of the runtime; do not treat it as a current migration tool.

[source-manifest.json](C:/Users/A5IN/Coding/learning/zig/draft1/docs/audit/source-manifest.json) records hashes/bytes of the tracked first-party evidence at the audited base, excluding the unrelated .agents deletion and generated lockfile. Test source is evidence of intended checks, not proof those checks pass.

| Reference | Exact pin | How it was used |
| --- | --- | --- |
| Local Taffy | `5f3f035e0a461db4f321af8e2ecf47abd2b709a0`, Cargo version 0.15.0 | Dimension types; leaf measurement/box adjustment; flex basis/distribution/freezing; block collapse/float context; grid structure; cache/rounding seams |
| Local Solid 2 | `2105ffb8ca2fced55f5fac0763177fc93f97c2c2`, solid-js 2.0.0-rc.21 | Universal renderer markers/mutation/lifecycle contract; client primitive exports; lazy modules, Loading/Reveal and refresh seams |
| Application dependencies | solid-js/universal rc.21; Vite plugin next.50; Vite 8.3.7; pinned QuickJS sources | Actual installed/project contract, not an assumption that the newer reference Vite plugin pin is installed |
| WebDX data | web-features 3.45.0, SHA-256 recorded in each inventory JSON | Reproducible feature names, per-key dates/spec URLs and Chrome support metadata |

Both local reference checkouts were inspected read-only and were clean when inspected. No installs/builds/experiments were placed in them. Their implementations are references, not the definition of all CSS. Taffy's local tree includes newer optional work (for example flex-wrap balance); post-2024 features are not automatically imported into this target. It also does not own a complete text shaper, style cascade, native widget set or GPU painter. Solid owns reactivity and component scheduling, not native box layout, platform controls or CSS parsing.

Further useful reference entry points:

- [Taffy dimensions](C:/Users/A5IN/Coding/reference/taffy/src/style/dimension.rs:1), [leaf](C:/Users/A5IN/Coding/reference/taffy/src/compute/leaf.rs:20), [block](C:/Users/A5IN/Coding/reference/taffy/src/compute/block.rs:1), [grid](C:/Users/A5IN/Coding/reference/taffy/src/compute/grid/mod.rs:1), [cache/rounding](C:/Users/A5IN/Coding/reference/taffy/src/compute/mod.rs:333).
- [CSS Snapshot 2024](https://www.w3.org/TR/css-2024/) is a specification-stability inventory, not itself a Baseline browser-support profile.
- [WebDX documentation](https://github.com/web-platform-dx/web-features/tree/main/docs) and [pinned data](https://unpkg.com/web-features@3.45.0/data.json) define the catalog extraction input.
- [CSS Flexbox Level 1, 2018](https://www.w3.org/TR/2018/CR-css-flexbox-1-20181119/) supplies the pre-cutoff algorithm used for the concrete flex counterexamples.
- [WPT CSS result families](https://wpt.fyi/results/css) are future conformance evidence, not results obtained in this audit.

Regenerate the metadata with `node tools/audit-catalog.mjs`, then the machine-readable assessment, catalog tables, coverage checklist/chart and source hashes with `node tools/audit-report.mjs`. The manual findings in this report must be re-reviewed when implementation changes; rerunning the generator does not re-audit the algorithms. Keep the source commit and fixture/test manifest together with any future compatibility claim.
