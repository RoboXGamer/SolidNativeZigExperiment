# HTML + CSS Feature Reference (Chrome-level, comprehensive)

Goal: exhaustive checklist of what a browser (Chrome) supports, to compare against the custom layout engine. Bulleted, grouped.

## HTML Elements (all)

### Root/document
- html, head, body, title, base, link, meta, style, script, noscript, template

### Sections
- body, article, section, nav, aside, h1-h6, header, footer, address, main, hgroup, search

### Grouping
- p, hr, pre, blockquote, ol, ul, menu, li, dl, dt, dd, figure, figcaption, div

### Text-level
- a, em, strong, small, s, cite, q, dfn, abbr, ruby, rt, rp, data, time, code, var, samp, kbd, sub, sup, i, b, u, mark, bdi, bdo, span, br, wbr

### Edits
- ins, del

### Embedded content
- picture, source, img, iframe, embed, object, param, video, audio, track, map, area, svg, math, canvas, (fenced frame)

### Tabular
- table, caption, colgroup, col, thead, tbody, tfoot, tr, td, th

### Forms
- form, label, input, button, select, datalist, optgroup, option, textarea, output, progress, meter, fieldset, legend

### Interactive
- details, summary, dialog, (popover attribute)

### Scripting/Web Components
- script, noscript, template, slot, canvas, (custom elements)

### Obsolete (deprecated)
- applet, basefont, center, dir, font, isindex, listing, menuitem, multicol, nextid, noembed, plaintext, strike, xmp, marquee, frameset/frame/noframes

## CSS Properties & Features (Chrome)

### Display & box
- display (block/inline/inline-block/flex/grid/flow-root/table/list-item/contents/none)
- box-sizing, width/height/min/max, aspect-ratio
- margin, padding, border (width/style/color), border-radius, outline, box-shadow
- overflow (visible/hidden/scroll/auto/clip), overflow-x/y, text-overflow, clip-path, mask

### Positioning
- position (static/relative/absolute/fixed/sticky), top/right/bottom/left, inset, z-index

### Flexbox
- flex-direction, flex-wrap, flex-flow, justify-content, align-items, align-content, align-self, justify-self, gap, row-gap, column-gap
- flex (grow/shrink/basis), order

### Grid
- grid-template-columns/rows, grid-template-areas, grid-template, grid-auto-columns/rows/flow
- grid-column/row, grid-area, place-items/content/self, subgrid

### Multi-column
- columns, column-count, column-width, column-gap, column-rule, column-span, column-fill

### Typography
- font, font-family, font-size, font-weight, font-style, font-variant, font-stretch, font-size-adjust
- line-height, letter-spacing, word-spacing, text-align, text-decoration, text-transform, text-indent, text-shadow
- white-space, word-break, overflow-wrap, hyphens, text-wrap (balance/pretty), text-overflow
- vertical-align, direction, unicode-bidi, writing-mode, text-orientation
- @font-face, variable fonts, font-palette

### Color & background
- color, opacity, background, background-color, background-image, background-size, background-position, background-repeat, background-clip, background-origin, background-attachment
- gradients (linear/radial/conic), background-blend-mode, mix-blend-mode
- color functions: rgb, hsl, hwb, lab, lch, oklab, oklch, color-mix, relative color
- color-scheme, forced-colors

### Transforms & effects
- transform, transform-origin, transform-style, perspective, perspective-origin, backface-visibility
- filter, backdrop-filter
- box-shadow, text-shadow, opacity, mix-blend-mode, isolation

### Motion
- transition (property/duration/timing/function/delay)
- animation, @keyframes, animation-* (name/duration/timing/delay/iteration/direction/fill/play-state)
- scroll-driven animations, view transitions

### Layout modern
- container queries (@container), container-type, container-name
- CSS nesting
- :has(), :not(), :nth-child(An+B of sel)
- @layer, @scope, @starting-style
- logical properties (inline-size, block-size, margin-inline, padding-block, border-inline, etc.)
- aspect-ratio, gap for flex/grid

### Responsive / units
- media queries (@media), @supports, @import
- units: px, em, rem, %, vw/vh/vmin/vmax, svh/lvh/dvh, ch, ex, lh, rlh, cqw/cqh/cqi/cqb/cqmin/cqmax
- clamp(), min(), max()

### Selectors & pseudo
- :hover, :active, :focus, :focus-visible, :focus-within, :checked, :disabled, :enabled, :required, :optional, :valid, :invalid, :placeholder-shown, :target, :empty, :first-child, :last-child, :nth-child, :not, :has, :is, :where
- ::before, ::after, ::first-line, ::first-letter, ::selection, ::placeholder, ::marker, ::backdrop, ::view-transition*

### Other
- cursor, pointer-events, user-select, resize, caret-color, accent-color, field-sizing
- scroll-behavior, scroll-snap-type/align, scroll-padding/margin
- overscroll-behavior
- touch-action
- will-change, contain, content-visibility
- variables (custom properties), calc(), env()
- counters (@counter-style)
- @property (typed custom props)
- @font-face, @keyframes, @media, @supports, @layer, @scope, @container, @page, @counter-style
- printing (@page, page-break-*)
- SVG/CSS integration (fill, stroke, etc.)
- color-adjust, print-color-adjust

## Currently Implemented in draft1
- Elements: root, column, row, label, button, input, text
- Layout: row/column direction, width, height, padding (per-side), margin (per-side), gap, grid columns (px/fr), min/max, aspect-ratio, box-sizing
- Block layout (partial, not 100% CSS): vertical block stacking, width resolution with content-box/border-box, sibling margin collapsing (positive and negative), simplified first-child/parent top margin collapsing, collapse-through of empty blocks, BFC via `overflow != visible`, child insets on the inline axis
- Flexbox: direction (row/column + reverse), wrap/wrap-reverse, gap, order, grow/shrink/shrink-scaled, flex-basis (explicit/auto/content), justify-content (start/center/end/space-between/around/evenly), align-items/align-self (start/center/end/stretch/baseline), align-content (start/center/end/stretch/space-*), auto margins, intrinsic min-content/max-content sizing, min/max clamping during flexing
- Style: backgroundColor, color, fontSize, border (per-side width/color), borderRadius, outline, boxShadow, overflow
- Defaults from the JS bridge (the custom elements are flex primitives): containers (`root`, `column`, `row`, `label`, `button`, `input`) default to `display: flex`; `flexDirection` defaults to `row` for `row`/`label`/`button`/`input` and `column` for `root`/`column`; `text` defaults to `display: block`. Explicit `display`/`flexDirection` styles override the defaults. Display and direction must agree, otherwise a box is sized on one axis and its children are laid out on the other.
- Events: onClick, onInput, value
- Text metrics: layout pulls advance widths, line heights and baseline ascent from an injected `MeasureFn`. The Raylib backend installs one backed by `MeasureText`, so intrinsic sizing, `flex-basis: content`, text line heights and baseline alignment use real font metrics. Headless tests fall back to a documented estimator (`0.5em` per byte, `1.2em` line box).
- Geometry: `Rect` follows the DOMRect shape (`x`/`y`/`width`/`height` plus derived `left`/`top`/`right`/`bottom`, `contains`, `inset`/`outset`, `intersect`); `Node.padding()`/`border()`/`margin()` expose the box rings once, so no module re-derives them.
- Overflow clipping: nested scissor via parent tracking

## Block layout gaps (not 100% CSS/Taffy parity)
- No floats, float context, or clearance (so no float-based layouts)
- No inline formatting context (IFC): widths and line heights now come from real font metrics, but text is still a single run — no line boxes, wrapping, inline-block baseline alignment, or inline fragmentation. `Text.wrap()` exists as the seam for a future IFC.
- Margin collapsing covers sibling pairs (including negative margins), collapse-through of empty blocks, and a simplified parent/first-child top collapse; missing parent-child bottom collapse and the full margin-collapse algorithm when padding, borders, clearance and floats interact
- `height: auto` sums measured content (`naturalHeight`), not a real block-size resolution; percentage heights and `auto`/`min-content`/`max-content` widths are not resolved per spec
- Shrink-to-fit widths, `display: flow-root`, `table`/`list-item`/`contents`, and blockification of flex/grid children are not implemented
- Block direction/writing modes, `float` interaction with BFC, and spec `min-width: auto` content sizing in normal flow are missing
- Still needs: a float context, an inline formatting context built on `Text.wrap()`, and a full block formatting context pass (Taffy's `compute/block.rs` is ~1900 lines plus supporting infrastructure)

## Not Implemented (Chrome gaps)
- All HTML elements beyond basic containers/text/buttons/inputs
- Block layout remaining gaps: see the section above (floats, IFC, full margin collapsing, auto/percentage sizing, flow-root/table/list-item, writing modes)
- Flexbox remaining gaps: percentage flex-basis, absolute flex items, writing modes, multi-line text intrinsic contribution (metrics are per-run, not per-line-box), spec-exact intrinsic contribution for nested flex containers
- Full grid (areas, auto-flow, subgrid)
- Positioning (absolute/relative/fixed/sticky)
- Overflow, clipping, scrolling
- Borders, border-radius, box-shadow
- Background images, gradients
- Transforms, transitions, animations
- Media/container queries, responsive units
- Typography beyond size/color
- Forms beyond input
- Accessibility attributes
- Focus, keyboard input, text input editing
- Selectors/pseudo beyond type
- CSS variables, calc, env
- Scroll snap, overscroll
- Blend modes, filters, backdrop-filter
- Multi-column, writing modes
- View transitions, starting styles