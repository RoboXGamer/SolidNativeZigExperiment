# Native Windows text

The Windows backend uses DirectWrite 2 and the Windows 10 per-monitor-v2 DPI APIs, linked through a C ABI in `src/text_backend.cpp`. The current native toolchain targets Windows 11. It replaces the GDI/Uniscribe implementation that rounded font sizes, advances and pointer hit coordinates to integers and rasterized entire runs at logical resolution. The application still uses Raylib/OpenGL for composition. No example font sizes, families or styles were changed for this improvement.

## Layout and typography

`CreateTextLayout`, rather than GDI-compatible layout, retains fractional CSS-pixel metrics. A bounded native layout cache shares the actual shaped layout between measurement, rasterization, caret placement, pointer hit testing and horizontal selection rectangles. Kerning is enabled; `"kern" off` disables it. Native line metrics also apply to empty input values.

The backend consumes ordered, quoted CSS family lists and maps the existing generic families to Windows fonts. A DirectWrite fallback builder tries the author families before system fallback. Language, weight, italic/oblique style, the existing NLS text transformations, fractional letter/word spacing, numeric/length tab stops and quoted OpenType feature tags (`on`, `off`, integer values) participate in the layout key. Zero-size tabs retain author indices while occupying zero width. Explicit sideways orientation rotates the raster. The UI core continues to own wrapping, line boxes and CSS presentation.

Caret positions come from the complete shaped run, including kerning, ligatures and bidi ordering. They are not measured from independently shaped prefixes. Native hit positions are mapped back to author UTF-8 after transformations and constrained to the editor's extended grapheme boundaries. Horizontal selections use DirectWrite's visual range rectangles, including disjoint bidi ranges. Pointer hit testing includes the input's horizontal scroll. IMM candidate/composition positions retain fractional logical coordinates until conversion to client pixels.

## Device pixels and caches

The application requests per-monitor-v2 DPI awareness before window creation and enables Raylib high-DPI support. Layout and input use logical pixels; glyph coverage and offscreen compositor targets use physical pixels. Scale changes clear device textures and rebuild the scene. Clipping converts fragment coordinates back into logical space. The existing premultiplied compositor is preserved.

`IDWriteTextRenderer` supplies the shaped fallback glyph runs to `CreateGlyphRunAnalysis` with natural symmetric grayscale antialiasing. Transparent white RGBA coverage avoids background-dependent RGB ClearType fringes. Raster bounds retain negative italic bearings and ink outside the advance box. Fractional physical origins are included in raster keys; the corresponding quad is aligned to the device grid. Positive uniform transforms also choose a matching raster scale. Integer translations and color changes reuse coverage.

Native layouts have exact length-delimited keys and a 256-entry LRU limit; runs over 16 KiB are not retained in that LRU. Logical metric and GPU texture keys include all native typography inputs. Device textures additionally depend on raster scale and x/y fractional phase, with 512-entry/32-MiB eviction thresholds. A single larger texture can temporarily exceed the byte threshold. Queued GPU work is flushed before eviction. `WM_FONTCHANGE` refreshes the font collection and invalidates layout, metric and raster caches together.

## Validation

Run `zig build test-native` with a working Windows OpenGL context. It runs font contracts and existing compositor pixel regressions in a hidden window, without mouse automation. Checks cover:

- Fractional sizes (13.1/13.4 px), advances, line metrics, letter/word spacing and 31.25-px/zero tab stops.
- Ordered missing-family fallback, Calibri's actual OpenType ligature substitution, full-run kerned carets, transformed author offsets, RTL hit testing and mixed bidi selection rectangles.
- Negative italic bearings, sideways coverage, fractional device phases, integer-translation/color reuse, DPI eviction and font collection invalidation.
- Latin, Devanagari, Arabic, Hebrew, Chinese/Japanese/Korean, combining accents and ZWJ emoji. The test inspects actual glyph indices and rejects missing glyphs; results depend on installed Windows fonts.
- Physical compositor targets and identical glyph alpha through input and ancestor clipping at explicit 100%, 125%, 150% and 200% scales. This seam exercises every scale on one monitor. Existing gradient, opacity, rounded clipping, transform and background-image tests still run.

The tic-tac-toe production bundle, native build and hidden-window smoke are also checked. Core Zig tests and the root `pnpm test` suite cover layout and package/bridge behavior. The application smoke on this machine uses the real 125% display scale (1280×720 logical, 1600×900 framebuffer).

## Limits

This is a native text pipeline improvement, not complete browser typography/CSS compatibility. Downloadable `@font-face`, variable font axes, full Unicode CSS case mapping, browser-equivalent international line breaking, full vertical writing/ruby layout and color emoji painting are not implemented here. Emoji use the system's shaped monochrome outlines. Arbitrary rotation, perspective and nonuniform transforms reuse DPI-scale coverage and may resample it. ClearType/system gamma tuning and browser-identical pixel output are not claimed.

Tests exercise scale changes through an explicit renderer seam and a real 125% application smoke. Moving a live window between monitors, subjective font appearance, and physical IME interaction remain user validation. The separate JS/CSS hover latency remains outside this work; this change does not fix or measure that latency.

API references: [DirectWrite character spacing](https://learn.microsoft.com/en-us/windows/win32/directwrite/justification--kerning--and-spacing), [DirectWrite glyph run analysis](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_2/nf-dwrite_2-idwritefactory2-createglyphrunanalysis), and [DirectWrite with a custom rendering stack](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-directwrite).
