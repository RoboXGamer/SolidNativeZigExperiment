# CSS feature inventory through 2024

Pinned WebDX web-features 3.45.0; cutoff 2024-12-31; source SHA-256 `bcda8f1fd702fd2c7cc71779d35430022cf57b56dcd9415f3bb8ee14486eb3b4`.

288 feature groups and 2293 CSS compatibility keys meet this extraction rule. 22 groups have a partial native analogue; the rest have no implemented end-to-end CSS feature path. **No group is certified conformant.** A native analogue is not support for CSS syntax, all values, or all interactions. 288 groups are not 288 equally sized specification obligations.

A group may have subfeatures added after 2024; the JSON includes only keys individually available by the cutoff. Groups whose overall date is later are included only for their older keys. Counts include CSS hooks of HTML/SVG/MathML features. Deprecated catalog records are retained so omissions are explicit, not silently counted as modern requirements.

Regenerate the data using `node tools/audit-catalog.mjs`, then the report using `node tools/audit-report.mjs`. Neither command runs application code. Data model: [WebDX](https://github.com/web-platform-dx/web-features/tree/main/docs); raw pinned data: [web-features@3.45.0](https://unpkg.com/web-features@3.45.0/data.json).

| Feature ID | Name | Target CSS keys | Source status |
| --- | --- | ---: | --- |
| absolute-positioning | Absolute positioning | 1 | Absent: no complete CSS feature implementation path. |
| align-content-block | align-content in block layouts | 1 | Absent: no complete CSS feature implementation path. |
| all | all | 1 | Absent: no complete CSS feature implementation path. |
| alt-text-generated-content | Alt text for generated content | 1 | Absent: no complete CSS feature implementation path. |
| animation-composition | animation-composition | 1 | Absent: no complete CSS feature implementation path. |
| animations-css | Animations (CSS) | 51 | Absent: no complete CSS feature implementation path. |
| appearance | appearance | 14 | Absent: no complete CSS feature implementation path. |
| aspect-ratio | aspect-ratio | 2 | Zero-height fallback only; BOX-07. |
| attr-contents | attr() (content only) | 1 | Absent: no complete CSS feature implementation path. |
| autonomous-custom-elements | Autonomous custom elements | 1 | Absent: no complete CSS feature implementation path. |
| backdrop | ::backdrop | 3 | Absent: no complete CSS feature implementation path. |
| backdrop-filter | backdrop-filter | 1 | Absent: no complete CSS feature implementation path. |
| background | background | 12 | Absent: no complete CSS feature implementation path. |
| background-attachment | background-attachment | 4 | Absent: no complete CSS feature implementation path. |
| background-blend-mode | background-blend-mode | 2 | Absent: no complete CSS feature implementation path. |
| background-clip | background-clip | 5 | Absent: no complete CSS feature implementation path. |
| background-color | background-color | 2 | Six-digit hex solids only; PAINT-01. |
| background-image | background-image | 3 | Absent: no complete CSS feature implementation path. |
| background-origin | background-origin | 5 | Absent: no complete CSS feature implementation path. |
| background-position | background-position | 16 | Absent: no complete CSS feature implementation path. |
| background-repeat | background-repeat | 9 | Absent: no complete CSS feature implementation path. |
| background-size | background-size | 5 | Absent: no complete CSS feature implementation path. |
| before-after | ::before and ::after | 4 | Absent: no complete CSS feature implementation path. |
| border-image | Border images | 20 | Absent: no complete CSS feature implementation path. |
| border-radius | border-radius | 16 | Uniform/top-left radius only; PAINT-03. |
| borders | Borders | 162 | Numeric side widths/colors, incomplete paint; PAINT-02. |
| box-shadow | box-shadow | 5 | Approximate rectangle; no blur; PAINT-04. |
| box-sizing | box-sizing | 3 | Horizontal block adjustment only; BOX-05. |
| calc | calc() | 4 | Absent: no complete CSS feature implementation path. |
| calc-constants | calc() keywords | 5 | Absent: no complete CSS feature implementation path. |
| cap | cap unit | 1 | Absent: no complete CSS feature implementation path. |
| caret-color | caret-color | 3 | Absent: no complete CSS feature implementation path. |
| cascade-layers | Cascade layers | 3 | Absent: no complete CSS feature implementation path. |
| case-insensitive-attributes | Case-insensitive attribute selector | 1 | Absent: no complete CSS feature implementation path. |
| ch | ch unit | 1 | Absent: no complete CSS feature implementation path. |
| charset | @charset | 1 | Absent: no complete CSS feature implementation path. |
| clip-path | clip-path | 6 | Absent: no complete CSS feature implementation path. |
| clip-path-animatable | Animatable clipping paths | 1 | Absent: no complete CSS feature implementation path. |
| clip-path-boxes | Clip path boxes | 3 | Absent: no complete CSS feature implementation path. |
| color | Color | 4 | Six-digit hex color and manual inheritance only; PAINT-01. |
| color-function | color() | 2 | Absent: no complete CSS feature implementation path. |
| color-gamut | color-gamut media query | 4 | Absent: no complete CSS feature implementation path. |
| color-mix | color-mix() | 1 | Absent: no complete CSS feature implementation path. |
| color-scheme | color-scheme | 5 | Absent: no complete CSS feature implementation path. |
| colrv0 | COLRv0 | 1 | Absent: no complete CSS feature implementation path. |
| column-breaks | Column breaks | 3 | Absent: no complete CSS feature implementation path. |
| column-fill | column-fill | 3 | Absent: no complete CSS feature implementation path. |
| column-span | column-span | 3 | Absent: no complete CSS feature implementation path. |
| conic-gradients | Conic gradients | 3 | Absent: no complete CSS feature implementation path. |
| contain | contain | 4 | Absent: no complete CSS feature implementation path. |
| contain-inline-size | Inline-size containment | 1 | Absent: no complete CSS feature implementation path. |
| contain-intrinsic-size | contain-intrinsic-size | 11 | Absent: no complete CSS feature implementation path. |
| contain-layout | Layout containment | 1 | Absent: no complete CSS feature implementation path. |
| contain-paint | Paint containment | 1 | Absent: no complete CSS feature implementation path. |
| contain-size | Size containment | 1 | Absent: no complete CSS feature implementation path. |
| contain-style | Style containment | 1 | Absent: no complete CSS feature implementation path. |
| container-queries | Container queries (size) | 9 | Absent: no complete CSS feature implementation path. |
| content | Content | 11 | Absent: no complete CSS feature implementation path. |
| content-visibility | content-visibility | 3 | Absent: no complete CSS feature implementation path. |
| counter-set | counter-set | 3 | Absent: no complete CSS feature implementation path. |
| counter-style | @counter-style | 9 | Absent: no complete CSS feature implementation path. |
| counters | Counters (CSS) | 7 | Absent: no complete CSS feature implementation path. |
| cubic-bezier-easing | cubic-bezier() easing | 2 | Absent: no complete CSS feature implementation path. |
| currentcolor | currentColor | 15 | Absent: no complete CSS feature implementation path. |
| cursor | Cursor styles | 5 | Absent: no complete CSS feature implementation path. |
| custom-properties | Custom properties | 2 | Absent: no complete CSS feature implementation path. |
| default | :default | 1 | Absent: no complete CSS feature implementation path. |
| dir-pseudo | :dir() | 1 | Absent: no complete CSS feature implementation path. |
| display | Display | 5 | Custom block/flex dispatch; none/inline semantics missing; BOX-08. |
| display-contents | display: contents | 1 | Absent: no complete CSS feature implementation path. |
| display-flow-root | display: flow-root | 1 | Absent: no complete CSS feature implementation path. |
| display-list-item | display: list-item | 1 | Absent: no complete CSS feature implementation path. |
| display-mode | display-mode media query | 2 | Absent: no complete CSS feature implementation path. |
| display-table | display: table | 10 | Absent: no complete CSS feature implementation path. |
| dominant-baseline | dominant-baseline | 8 | Absent: no complete CSS feature implementation path. |
| dynamic-range | dynamic-range media query | 1 | Absent: no complete CSS feature implementation path. |
| em-unit | em unit | 1 | Absent: no complete CSS feature implementation path. |
| empty | :empty | 1 | Absent: no complete CSS feature implementation path. |
| ex | ex unit | 1 | Absent: no complete CSS feature implementation path. |
| exp-functions | Exponential functions (CSS) | 5 | Absent: no complete CSS feature implementation path. |
| file-selector-button | ::file-selector-button | 1 | Absent: no complete CSS feature implementation path. |
| filter | filter | 22 | Absent: no complete CSS feature implementation path. |
| first-letter | ::first-letter | 1 | Absent: no complete CSS feature implementation path. |
| first-line | ::first-line | 1 | Absent: no complete CSS feature implementation path. |
| fit-content | fit-content | 6 | Absent: no complete CSS feature implementation path. |
| fixed-positioning | Fixed positioning | 1 | Absent: no complete CSS feature implementation path. |
| flexbox | Flexbox | 144 | Substantial subset with algorithm defects; FLEX-01 through FLEX-07. |
| flexbox-gap | Flexbox gap | 3 | One numeric gap; no independent axes or percentages. |
| float-clear | float and clear | 9 | Absent: no complete CSS feature implementation path. |
| focus-visible | :focus-visible | 1 | Absent: no complete CSS feature implementation path. |
| focus-within | :focus-within | 1 | Absent: no complete CSS feature implementation path. |
| font-display | font-display | 1 | Absent: no complete CSS feature implementation path. |
| font-face | @font-face | 10 | Absent: no complete CSS feature implementation path. |
| font-family | font-family | 6 | Absent: no complete CSS feature implementation path. |
| font-family-system | System font | 1 | Absent: no complete CSS feature implementation path. |
| font-feature-settings | font-feature-settings | 2 | Absent: no complete CSS feature implementation path. |
| font-kerning | font-kerning | 4 | Absent: no complete CSS feature implementation path. |
| font-optical-sizing | font-optical-sizing | 3 | Absent: no complete CSS feature implementation path. |
| font-palette | font-palette | 8 | Absent: no complete CSS feature implementation path. |
| font-shorthand | Font shorthand | 7 | Absent: no complete CSS feature implementation path. |
| font-size | font-size | 12 | Numeric font size only; TEXT-01/02. |
| font-size-adjust | font-size-adjust | 5 | Absent: no complete CSS feature implementation path. |
| font-stretch | font-stretch | 13 | Absent: no complete CSS feature implementation path. |
| font-style | font-style | 5 | Absent: no complete CSS feature implementation path. |
| font-synthesis | font-synthesis | 4 | Absent: no complete CSS feature implementation path. |
| font-synthesis-small-caps | font-synthesis-small-caps | 3 | Absent: no complete CSS feature implementation path. |
| font-synthesis-style | font-synthesis-style | 3 | Absent: no complete CSS feature implementation path. |
| font-synthesis-weight | font-synthesis-weight | 3 | Absent: no complete CSS feature implementation path. |
| font-variant | font-variant | 9 | Absent: no complete CSS feature implementation path. |
| font-variant-alternates | font-variant-alternates | 17 | Absent: no complete CSS feature implementation path. |
| font-variant-caps | font-variant-caps | 14 | Absent: no complete CSS feature implementation path. |
| font-variant-east-asian | font-variant-east-asian | 20 | Absent: no complete CSS feature implementation path. |
| font-variant-ligatures | font-variant-ligatures | 19 | Absent: no complete CSS feature implementation path. |
| font-variant-numeric | font-variant-numeric | 18 | Absent: no complete CSS feature implementation path. |
| font-variant-position | font-variant-position | 2 | Absent: no complete CSS feature implementation path. |
| font-variation-settings | font-variation-settings | 1 | Absent: no complete CSS feature implementation path. |
| font-weight | font-weight | 7 | Absent: no complete CSS feature implementation path. |
| forced-colors | Forced colors | 1 | Absent: no complete CSS feature implementation path. |
| form-validity-pseudos | Form validity pseudo-classes | 8 | Absent: no complete CSS feature implementation path. |
| fullscreen | Fullscreen API | 1 | Absent: no complete CSS feature implementation path. |
| gradient-interpolation | Gradient interpolation | 12 | Absent: no complete CSS feature implementation path. |
| gradients | Gradients | 23 | Absent: no complete CSS feature implementation path. |
| grid | Grid | 69 | Basic fixed/fr columns; GRID-01/02. |
| grid-animation | Grid animation | 2 | Absent: no complete CSS feature implementation path. |
| has | :has() | 1 | Absent: no complete CSS feature implementation path. |
| host | Host | 2 | Absent: no complete CSS feature implementation path. |
| hsl | HSL | 4 | Absent: no complete CSS feature implementation path. |
| hwb | HWB | 2 | Absent: no complete CSS feature implementation path. |
| hyphenate-character | Hyphenate character | 2 | Absent: no complete CSS feature implementation path. |
| hyphens | Hyphenation | 17 | Absent: no complete CSS feature implementation path. |
| ic | ic unit | 1 | Absent: no complete CSS feature implementation path. |
| image-orientation | image-orientation | 3 | Absent: no complete CSS feature implementation path. |
| image-rendering | image-rendering | 3 | Absent: no complete CSS feature implementation path. |
| image-set | image-set() | 3 | Absent: no complete CSS feature implementation path. |
| import | @import | 1 | Absent: no complete CSS feature implementation path. |
| indeterminate | :indeterminate | 4 | Absent: no complete CSS feature implementation path. |
| individual-transforms | Individual transform properties | 7 | Absent: no complete CSS feature implementation path. |
| inherit-value | inherit | 2 | Absent: no complete CSS feature implementation path. |
| initial-value | initial | 1 | Absent: no complete CSS feature implementation path. |
| input-selectors | Input selectors | 3 | Absent: no complete CSS feature implementation path. |
| interaction | Interaction media queries | 4 | Absent: no complete CSS feature implementation path. |
| is | :is() | 2 | Absent: no complete CSS feature implementation path. |
| isolation | isolation | 1 | Absent: no complete CSS feature implementation path. |
| lab | Lab and LCH | 4 | Absent: no complete CSS feature implementation path. |
| lang | :lang() | 1 | Absent: no complete CSS feature implementation path. |
| layout-direction-override | Layout direction override | 10 | Absent: no complete CSS feature implementation path. |
| letter-spacing | letter-spacing | 2 | Absent: no complete CSS feature implementation path. |
| lh | lh unit | 1 | Absent: no complete CSS feature implementation path. |
| light-dark | light-dark() | 1 | Absent: no complete CSS feature implementation path. |
| line-break | line-break | 6 | Absent: no complete CSS feature implementation path. |
| line-height | line-height | 2 | Absent: no complete CSS feature implementation path. |
| linear-easing | linear() easing | 1 | Absent: no complete CSS feature implementation path. |
| link-selectors | Link selectors | 7 | Absent: no complete CSS feature implementation path. |
| list-style | List style | 67 | Absent: no complete CSS feature implementation path. |
| logical-properties | Logical properties | 262 | Absent: no complete CSS feature implementation path. |
| margin | margin | 10 | Numeric/auto subset with sentinel and ownership defects; BOX-02/03/04. |
| mask-type | mask-type | 3 | Absent: no complete CSS feature implementation path. |
| masks | Masks | 44 | Absent: no complete CSS feature implementation path. |
| mathml | MathML | 1 | Absent: no complete CSS feature implementation path. |
| media-queries | Media queries | 13 | Absent: no complete CSS feature implementation path. |
| media-query-range-syntax | Media query range syntax | 1 | Absent: no complete CSS feature implementation path. |
| min-max-clamp | min(), max(), and clamp() | 3 | Absent: no complete CSS feature implementation path. |
| min-max-content | min-content and max-content | 12 | Absent: no complete CSS feature implementation path. |
| min-max-width-height | Min and max width and height | 8 | Positive numeric clamp only; BOX-01/06. |
| mix-blend-mode | mix-blend-mode | 2 | Absent: no complete CSS feature implementation path. |
| modal | :modal | 1 | Absent: no complete CSS feature implementation path. |
| motion-path | Motion path | 35 | Absent: no complete CSS feature implementation path. |
| multi-column | Multi-column layout | 46 | Absent: no complete CSS feature implementation path. |
| named-color | Named colors | 3 | Absent: no complete CSS feature implementation path. |
| namespace | @namespace | 2 | Absent: no complete CSS feature implementation path. |
| nesting | Nesting | 1 | Absent: no complete CSS feature implementation path. |
| not | :not() | 2 | Absent: no complete CSS feature implementation path. |
| nth-child | :nth-child() | 6 | Absent: no complete CSS feature implementation path. |
| nth-child-of | :nth-child() of <selector> | 2 | Absent: no complete CSS feature implementation path. |
| nth-of-type | :nth-of-type() pseudo-classes | 5 | Absent: no complete CSS feature implementation path. |
| object-fit | object-fit | 6 | Absent: no complete CSS feature implementation path. |
| object-position | object-position | 1 | Absent: no complete CSS feature implementation path. |
| oklab | Oklab and OkLCh | 4 | Absent: no complete CSS feature implementation path. |
| opacity | opacity | 4 | Absent: no complete CSS feature implementation path. |
| outline | outline | 16 | Basic rectangle, not CSS outlines. |
| outlines | Outlines | 18 | Basic rectangle, not CSS outlines. |
| overflow | Overflow media queries | 2 | Rectangular clip and vertical wheel subset; SCROLL-01/02. |
| overflow-clip | overflow: clip | 4 | Rectangular clip, incorrect block-context implication; BLOCK-06. |
| overflow-shorthand | overflow | 17 | Absent: no complete CSS feature implementation path. |
| overflow-wrap | overflow-wrap | 4 | Absent: no complete CSS feature implementation path. |
| padding | padding | 5 | Numeric subset; explicit zero/control defaults are wrong; BOX-02. |
| page-breaks | Page breaks | 19 | Absent: no complete CSS feature implementation path. |
| page-selectors | Page selectors | 1 | Absent: no complete CSS feature implementation path. |
| page-setup | Page setup | 5 | Absent: no complete CSS feature implementation path. |
| paint-order | paint-order | 1 | Absent: no complete CSS feature implementation path. |
| path-shape | path() | 3 | Absent: no complete CSS feature implementation path. |
| physical-properties | Physical properties | 8 | Some physical size/edge style names only; no logical mapping or inset support. |
| placeholder | ::placeholder | 1 | Absent: no complete CSS feature implementation path. |
| placeholder-shown | :placeholder-shown | 2 | Absent: no complete CSS feature implementation path. |
| pointer-events | pointer-events | 9 | Absent: no complete CSS feature implementation path. |
| popover | Popover | 2 | Absent: no complete CSS feature implementation path. |
| position | Position | 1 | Absent: no complete CSS feature implementation path. |
| prefers-color-scheme | prefers-color-scheme media query | 1 | Absent: no complete CSS feature implementation path. |
| prefers-contrast | prefers-contrast media query | 1 | Absent: no complete CSS feature implementation path. |
| prefers-reduced-motion | prefers-reduced-motion media query | 1 | Absent: no complete CSS feature implementation path. |
| q-unit | Q unit | 1 | Absent: no complete CSS feature implementation path. |
| quotes | Quotes | 3 | Absent: no complete CSS feature implementation path. |
| read-write-pseudos | :read-only and :read-write | 2 | Absent: no complete CSS feature implementation path. |
| rect-xywh | rect() and xywh() | 2 | Absent: no complete CSS feature implementation path. |
| registered-custom-properties | Registered custom properties | 4 | Absent: no complete CSS feature implementation path. |
| relative-color | Relative colors | 9 | Absent: no complete CSS feature implementation path. |
| relative-positioning | Relative positioning | 1 | Absent: no complete CSS feature implementation path. |
| rem | rem | 1 | Absent: no complete CSS feature implementation path. |
| resolution | resolution media query | 6 | Absent: no complete CSS feature implementation path. |
| resolution-compat | resolution media query (compatibility prefixes) | 3 | Absent: no complete CSS feature implementation path. |
| revert-value | revert | 1 | Absent: no complete CSS feature implementation path. |
| rgb | RGB | 7 | Absent: no complete CSS feature implementation path. |
| rlh | rlh unit | 1 | Absent: no complete CSS feature implementation path. |
| root | :root | 1 | Absent: no complete CSS feature implementation path. |
| round-mod-rem | round(), mod(), and rem() | 6 | Absent: no complete CSS feature implementation path. |
| ruby-align | ruby-align | 5 | Absent: no complete CSS feature implementation path. |
| ruby-position | ruby-position | 3 | Absent: no complete CSS feature implementation path. |
| safe-area-inset | Safe area inset environment variables | 5 | Absent: no complete CSS feature implementation path. |
| scope-pseudo | :scope (pseudo-class) | 2 | Absent: no complete CSS feature implementation path. |
| scripting | scripting media query | 1 | Absent: no complete CSS feature implementation path. |
| scroll-behavior | scroll-behavior | 3 | Absent: no complete CSS feature implementation path. |
| scroll-snap | Scroll snap | 44 | Absent: no complete CSS feature implementation path. |
| scrollbar-gutter | scrollbar-gutter | 3 | Absent: no complete CSS feature implementation path. |
| scrollbar-width | scrollbar-width | 4 | Absent: no complete CSS feature implementation path. |
| selectors | Selectors (core) | 12 | Absent: no complete CSS feature implementation path. |
| shadow-parts | Shadow parts | 1 | Absent: no complete CSS feature implementation path. |
| shape-outside | shape-outside | 9 | Absent: no complete CSS feature implementation path. |
| shapes | shapes | 6 | Absent: no complete CSS feature implementation path. |
| slot | <slot> | 1 | Absent: no complete CSS feature implementation path. |
| starting-style | @starting-style | 1 | Absent: no complete CSS feature implementation path. |
| state | :state() | 1 | Absent: no complete CSS feature implementation path. |
| static-positioning | Static positioning | 1 | Custom normal flow only, not the full CSS box tree. |
| steps-easing | steps() easing | 2 | Absent: no complete CSS feature implementation path. |
| sticky-positioning | Sticky positioning | 2 | Absent: no complete CSS feature implementation path. |
| subgrid | Subgrid | 2 | Absent: no complete CSS feature implementation path. |
| supports | @supports | 5 | Absent: no complete CSS feature implementation path. |
| supports-compat | @supports (compatibility prefix) | 1 | Absent: no complete CSS feature implementation path. |
| svg | SVG | 27 | Absent: no complete CSS feature implementation path. |
| svg-filters | SVG filters | 11 | Absent: no complete CSS feature implementation path. |
| system-color | System colors | 1 | Absent: no complete CSS feature implementation path. |
| tab-size | tab-size | 2 | Absent: no complete CSS feature implementation path. |
| table | Tables | 13 | Absent: no complete CSS feature implementation path. |
| target | :target | 1 | Absent: no complete CSS feature implementation path. |
| target-text | ::target-text | 1 | Absent: no complete CSS feature implementation path. |
| text-align | text-align | 7 | Absent: no complete CSS feature implementation path. |
| text-align-last | text-align-last | 2 | Absent: no complete CSS feature implementation path. |
| text-combine-upright | text-combine-upright | 3 | Absent: no complete CSS feature implementation path. |
| text-decoration | text-decoration | 19 | Absent: no complete CSS feature implementation path. |
| text-decoration-skip-ink | text-decoration-skip-ink | 3 | Absent: no complete CSS feature implementation path. |
| text-emphasis | text-emphasis | 19 | Absent: no complete CSS feature implementation path. |
| text-indent | text-indent | 1 | Absent: no complete CSS feature implementation path. |
| text-orientation | text-orientation | 4 | Absent: no complete CSS feature implementation path. |
| text-overflow | Text overflow | 3 | Absent: no complete CSS feature implementation path. |
| text-shadow | text-shadow | 2 | Absent: no complete CSS feature implementation path. |
| text-stroke-fill | Text stroke and fill  (compatibility prefixes) | 4 | Absent: no complete CSS feature implementation path. |
| text-transform | text-transform | 8 | Absent: no complete CSS feature implementation path. |
| text-underline-offset | text-underline-offset | 3 | Absent: no complete CSS feature implementation path. |
| text-underline-position | text-underline-position | 6 | Absent: no complete CSS feature implementation path. |
| text-wrap | text-wrap | 10 | Absent: no complete CSS feature implementation path. |
| text-wrap-balance | text-wrap: balance | 2 | Absent: no complete CSS feature implementation path. |
| touch-action | touch-action | 6 | Absent: no complete CSS feature implementation path. |
| transform-box | transform-box | 6 | Absent: no complete CSS feature implementation path. |
| transforms2d | 2D transforms | 30 | Absent: no complete CSS feature implementation path. |
| transforms3d | 3D transforms | 26 | Absent: no complete CSS feature implementation path. |
| transition-behavior | transition-behavior | 1 | Absent: no complete CSS feature implementation path. |
| transitions | Transitions (CSS) | 25 | Absent: no complete CSS feature implementation path. |
| trig-functions | Trigonometric functions (CSS) | 7 | Absent: no complete CSS feature implementation path. |
| two-value-display | Two-value display property | 1 | Absent: no complete CSS feature implementation path. |
| unset-value | unset | 1 | Absent: no complete CSS feature implementation path. |
| update | Update frequency media query | 1 | Absent: no complete CSS feature implementation path. |
| user-action-pseudos | User action pseudo-classes | 6 | Absent: no complete CSS feature implementation path. |
| user-pseudos | :user-valid and :user-invalid | 2 | Absent: no complete CSS feature implementation path. |
| vertical-align | vertical-align | 9 | Absent: no complete CSS feature implementation path. |
| vertical-form-controls | Vertical form controls | 1 | Absent: no complete CSS feature implementation path. |
| viewport-unit-variants | Small, large, and dynamic viewport units | 5 | Absent: no complete CSS feature implementation path. |
| viewport-units | Viewport units | 4 | Absent: no complete CSS feature implementation path. |
| visibility | visibility | 4 | Absent: no complete CSS feature implementation path. |
| webvtt | WebVTT | 1 | Absent: no complete CSS feature implementation path. |
| where | :where() | 2 | Absent: no complete CSS feature implementation path. |
| white-space | white-space | 8 | Absent: no complete CSS feature implementation path. |
| white-space-collapse | white-space-collapse | 5 | Absent: no complete CSS feature implementation path. |
| width-height | Width and height | 9 | Positive numeric dimensions only; BOX-01/05. |
| will-change | will-change | 4 | Absent: no complete CSS feature implementation path. |
| word-break | word-break | 4 | Absent: no complete CSS feature implementation path. |
| word-spacing | word-spacing | 2 | Absent: no complete CSS feature implementation path. |
| writing-mode | writing-mode | 4 | Absent: no complete CSS feature implementation path. |
| z-index | z-index | 4 | Absent: no complete CSS feature implementation path. |
| zoom | zoom | 1 | Absent: no complete CSS feature implementation path. |

## Chrome 131 supplement

This is separate from cross-browser Baseline: numeric Chrome support <=131 for additional keys in the same WebDX dataset. It is a discovery supplement, not a complete export of historical Chromium BCD/WPT or experimental/prefixed features. Those require a separately frozen oracle. Chrome 131 shipped in November 2024; 132 shipped in January 2025. See the official [131](https://developer.chrome.com/release-notes/131) and [132](https://developer.chrome.com/release-notes/132) release notes.

| Feature ID | Name | Additional CSS keys |
| --- | --- | ---: |
| absolute-positioning | Absolute positioning | 3 |
| accent-color | accent-color | 4 |
| active-view-transition | Active view transition | 2 |
| alignment-baseline | alignment-baseline | 9 |
| anchor-positioning | Anchor positioning | 165 |
| anchor-positioning-animations | Anchor positioning animations and transitions | 2 |
| anchor-positioning-position-visibility-plurals | anchors-valid and anchors-visible | 1 |
| animations-css | Animations (CSS) | 2 |
| autofill | :autofill | 1 |
| background-attachment | background-attachment | 1 |
| background-clip-text | background-clip: text | 2 |
| baseline-shift | baseline-shift | 3 |
| baseline-source | baseline-source | 4 |
| box-decoration-break | box-decoration-break | 3 |
| calc-size | calc-size() | 1 |
| clip | clip | 4 |
| colrv1 | COLRv1 | 1 |
| column-breaks | Column breaks | 12 |
| container-style-queries | Container style queries | 1 |
| content | Content | 1 |
| content-visibility | content-visibility | 1 |
| counter-style | @counter-style | 1 |
| cross-document-view-transitions | Cross-document view transitions | 1 |
| cursor | Cursor styles | 34 |
| details-content | ::details-content | 1 |
| device-queries | Device media queries | 3 |
| display | Display | 1 |
| display-animation | display animation | 4 |
| display-contents | display: contents | 1 |
| display-list-item | display: list-item | 1 |
| display-mode | display-mode media query | 3 |
| display-ruby | display: ruby | 2 |
| field-sizing | field-sizing | 3 |
| flexbox | Flexbox | 1 |
| font-face | @font-face | 2 |
| font-family-math | Math font family | 1 |
| font-metric-overrides | Font metric overrides | 3 |
| font-palette-animation | font-palette animation | 2 |
| font-variant-emoji | font-variant-emoji | 5 |
| forced-colors | Forced colors | 4 |
| fullscreen | Fullscreen API | 1 |
| highlight | Custom highlights | 1 |
| host-context | :host-context() | 1 |
| hyphenate-limit-chars | Hyphenate limit chars | 2 |
| hyphens | Hyphenation | 37 |
| initial-letter | initial-letter | 2 |
| interpolate-size | interpolate-size | 3 |
| justify-self-block | justify-self in block layouts | 2 |
| marker | ::marker | 2 |
| masks | Masks | 26 |
| mathml | MathML | 5 |
| media-queries | Media queries | 2 |
| mix-blend-mode | mix-blend-mode | 1 |
| multi-column | Multi-column layout | 1 |
| nth-child | :nth-child() | 4 |
| object-view-box | object-view-box | 2 |
| opacity-svg | Opacity (SVG) | 2 |
| overflow-anchor | overflow-anchor | 3 |
| overflow-overlay | overflow: overlay | 1 |
| overlay | overlay | 3 |
| page-break-aliases | Page break aliases | 15 |
| page-breaks | Page breaks | 12 |
| page-orientation | page-orientation | 1 |
| page-selectors | Page selectors | 2 |
| page-setup | Page setup | 16 |
| paint | paint() | 1 |
| path-shape | path() | 1 |
| picture-in-picture | Picture-in-picture (video) | 2 |
| prefers-color-scheme | prefers-color-scheme media query | 1 |
| prefers-reduced-transparency | prefers-reduced-transparency media query | 1 |
| rcap | rcap unit | 1 |
| rch | rch unit | 1 |
| resize | resize (CSS property) | 4 |
| rex | rex unit | 1 |
| ric | ric unit | 1 |
| scope | @scope | 1 |
| scroll-driven-animations | Scroll-driven animations | 26 |
| scrollbar-color | scrollbar-color | 2 |
| selection | ::selection | 1 |
| shape-outside | shape-outside | 1 |
| spelling-grammar-error | ::spelling-error and ::grammar-error | 2 |
| svg | SVG | 37 |
| svg-filters | SVG filters | 1 |
| system-color | System colors | 3 |
| text-decoration | text-decoration | 4 |
| text-decoration-line-blink | text-decoration-line: blink | 1 |
| text-decoration-selection | text-decoration in ::selection | 1 |
| text-decoration-spelling-grammar | Spelling and grammar text decorations | 2 |
| text-size-adjust | text-size-adjust | 4 |
| text-spacing-trim | text-spacing-trim | 5 |
| text-transform | text-transform | 1 |
| text-wrap-pretty | text-wrap: pretty | 2 |
| time-relative-selectors | Time-relative pseudo-selectors | 2 |
| touch-action | touch-action | 4 |
| transition-behavior | transition-behavior | 1 |
| user-select | user-select | 5 |
| vertical-form-controls | Vertical form controls | 1 |
| view-transition-class | view-transition-class | 2 |
| view-transitions | View transitions | 7 |
| webvtt | WebVTT | 1 |
| webxr-dom-overlays | DOM overlays for WebXR | 1 |
| widows-orphans | Widows and orphans | 2 |
| window-controls-overlay | Window Controls Overlay | 5 |
| word-break-auto-phrase | word-break: auto-phrase | 1 |
| word-break-break-word | word-break: break-word | 1 |
| writing-mode-svg-values | writing-mode SVG 1.1 values | 6 |
