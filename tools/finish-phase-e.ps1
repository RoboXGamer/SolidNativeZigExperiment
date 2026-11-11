$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repo
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8([string]$Path, [string]$Content) { [IO.File]::WriteAllText((Join-Path $repo $Path), $Content, $utf8) }
function Step([string]$Name, [scriptblock]$Command) {
    Write-Host "`n>>> $Name" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Name failed (exit $LASTEXITCODE); stopping before merge." }
}

# Correct the last unsafe-center edge case; auto margins still absorb only positive space.
$path = 'modules/ui_core/layout_flex.zig'
$source = [IO.File]::ReadAllText((Join-Path $repo $path))
$source = $source.Replace('if (remaining > 0) offset = remaining * 0.5;', 'offset = remaining * 0.5;')
$source = $source.Replace("if (info.cross_before_auto and info.cross_after_auto) {`r`n                offset = remaining * 0.5;", "if (info.cross_before_auto and info.cross_after_auto) {`r`n                if (remaining > 0) offset = remaining * 0.5;")
$source = $source.Replace("if (info.cross_before_auto and info.cross_after_auto) {`n                offset = remaining * 0.5;", "if (info.cross_before_auto and info.cross_after_auto) {`n                if (remaining > 0) offset = remaining * 0.5;")
Write-Utf8 $path $source

$package = Get-Content package.json -Raw | ConvertFrom-Json
$package.scripts.test = $package.scripts.test.Replace('npm run ', 'pnpm run ')
$package.scripts | Add-Member setup 'node tools/setup.mjs' -Force
$package.scripts | Add-Member 'test:native' 'zig build test-native' -Force
$package.scripts | Add-Member 'test:smoke' 'node tools/smoke-native.mjs' -Force
Write-Utf8 'package.json' (($package | ConvertTo-Json -Depth 10) + "`n")

Write-Utf8 'docs/tasks/phase-e-broaden-css.md' @'
# Phase E implementation and verification — 2026-11-12

This supersedes the initial handoff, whose completion claims were not supported
by application build or framebuffer tests. The PR's executable scope is the five
subsystems assigned in the Phase E implementation brief; this is not a claim of
complete Chrome/Baseline compatibility.

## Implemented paths and their owners

- Positioning: `modules/ui_core/scene.zig`. Relative/absolute/fixed/sticky,
  positioned/transformed containing blocks, out-of-flow extraction, percentage
  re-resolution at the actual containing block, fixed subtrees, sticky descendant
  offsets, auto margins and self alignment. Paint order isolates nested stacking
  contexts; transformed input uses the same composed matrices as drawing.
- Grid: `modules/ui_core/layout_grid.zig`. Balanced repeat/minmax parsing,
  named lines/areas, numeric lines/spans, implicit row/column patterns, dense and
  sparse placement, column-flow wrapping, frozen fractional minima, spanning
  contributions, auto-fit collapse, content/item alignment and intrinsic heights.
- Alignment: `layout_flex.zig`, `layout_grid.zig`, and the Solid style adapter.
  Place shorthands, safe/unsafe alignment, physical/logical start/end and RTL.
- Paint: `paint.zig`, `gradient.zig`, `transform.zig`, `src/renderer.zig` and
  `src/shaders`. Cached multi-stop linear/radial/conic backgrounds; parsed shadow
  layers with separable Gaussian blur, spread and inset masks; rounded clipping;
  subtree opacity composition; composed affine transforms for all content.
- Motion: `animation.zig`, `transitions.zig`, and the native event loop. Property
  changes start/retarget numeric, color and transform transitions; layout changes
  move siblings. Delay, duration, cubic-bezier and step timing are evaluated by
  the host. Frame wakeups stop when transitions settle.

## Phase A–D integration repairs

- Fixed a Zig 0.17 `ArrayList` API error in the multiline painter that core tests
  previously never instantiated. The full application now builds.
- Replaced estimated Windows ascent/descent and separate measure/draw behavior
  with a shared Uniscribe shaping/raster path and font fallback. Native checks
  exercise Latin, Indic and Arabic metrics and shaped glyph texture creation.
- Replaced the small combining-mark list with Unicode 16.0 extended grapheme
  segmentation, checked against the checked-in official GraphemeBreakTest corpus.
- Preserved the author tree while collapsing normal/nowrap scene text so layout
  and paint share whitespace. Fixed empty optional CSS transport, inherited text
  style handling and percentage line-height's font-size basis.
- Fixed focus ordering for positive tabindex and positioned controls, transformed
  pointer caret coordinates, initial click placement, and scrolling along the
  targeted ancestor chain. The native host positions the Windows IME candidate UI.

## Repeatable gates

Run from the project directory on Windows with Zig 0.17.0, Node and pnpm:

```powershell
pnpm run setup
pnpm test
pnpm run build:ui
zig build test
zig build test-native
zig build
pnpm run test:smoke
```

`test-native` creates a hidden real OpenGL window and checks framebuffer pixels
for intermediate gradient stops, radial/conic colors, subtree opacity, rounded
descendant clipping and transformed content. It also exercises native text
shaping. `test:smoke` runs the actual bundled Solid/QuickJS application for three
hidden frames and requires a successful scene/render completion marker.

The new regressions retain the three failures from the PR review: nested stacking
isolation, minmax/fr redistribution and column auto-placement. Existing A–D suites
remain in the same gate. Manual IME candidate/composition behavior is not certified
by the automated smoke test.

## Compatibility boundary

No full WPT/browser oracle has been run. These regression gates establish their
named cases, not every CSS value/context or 100% CSS Grid/Chrome conformance.
Stylesheets/selectors/cascade, custom properties, query families, subgrid, tables,
ruby, full browser controls/accessibility and the remaining catalog features are
separate compatibility work. The 2024/2025 catalogs and issues remain the source
of that backlog; their historical status labels are not current conformance data.
The older audit's broader Phase E/F roadmap is not completed by one implementation
PR. No Baseline issue is automatically closed by this PR on the strength of
helper tests or a transported property alone.
'@

$readme = Get-Content README.md -Raw
$readme = $readme.Replace('block/flex layout, basic grid columns', 'block/flex/grid layout, positioning and transitions')
$readme = $readme.Replace('the Raylib backend passes `MeasureText`', 'the Windows sample shares Uniscribe shaping between measurement and paint')
$readme = $readme.Replace("git clone https://github.com/quickjs-ng/quickjs.git vendor/quickjs`r`ngit -C vendor/quickjs checkout 6a9fe9af5ca0bf7c49ae697edef44864272317d1", 'node tools/setup.mjs')
$readme = $readme.Replace("git clone https://github.com/quickjs-ng/quickjs.git vendor/quickjs`ngit -C vendor/quickjs checkout 6a9fe9af5ca0bf7c49ae697edef44864272317d1", 'node tools/setup.mjs')
$cut = $readme.IndexOf('Existing checks are')
if ($cut -ge 0) { $readme = $readme.Substring(0, $cut) }
$readme += @'
The implemented A–E paths now include the native select control, box/block/flex
layout, expanded grid/positioning/alignment, shaped text, scrolling and editing,
cached paint effects, subtree transforms/opacity and runtime transitions. Native
render tests and an actual Solid/QuickJS application smoke test supplement the
core and JavaScript suites. See [the current implementation and verification
handoff](docs/tasks/phase-e-broaden-css.md) for commands, ownership and limits.

The Windows host waits for events while idle and schedules frames for active
JavaScript timers or native transitions. Paint textures are cached; tree/layout
updates still rebuild the scene. This is a native UI experiment, not a complete
browser engine or a released desktop toolkit. Stylesheet/cascade/query systems,
advanced CSS families, complete controls/accessibility and full browser-oracle
conformance remain in the catalog backlog. The 2026-11-11 audit is historical;
its old percentages must not be treated as current measurements.
'@
Write-Utf8 'README.md' ($readme + "`n")

Step 'Format changed Zig sources' {
    $files = @((git diff --name-only --diff-filter=ACM), (git ls-files --others --exclude-standard)) | ForEach-Object { $_ } | Where-Object { $_ -like '*.zig' }
    & zig fmt @files
}
Step 'Pinned QuickJS setup' { node tools/setup.mjs }
Step 'Solid and bridge suites' { pnpm test }
Step 'Production UI build' { pnpm run build:ui }
Step 'Phase A-E core regressions' { zig build test }
Step 'Native framebuffer and shaping checks' { zig build test-native }
Step 'Native application build' { zig build }
Step 'Real Solid/QuickJS application smoke' { node tools/smoke-native.mjs }
Step 'Patch whitespace check' { git diff --check }

Step 'Commit verified implementation' {
    git add build.zig README.md package.json modules/ui_core packages/solid-zig/src/native.js packages/solid-zig/tests/text-overflow.mjs src/windows.zig src/renderer.zig src/render_check.zig src/text_backend.c src/text_backend.zig src/shaders tools/setup.mjs tools/smoke-native.mjs tools/generate-graphemes.mjs tools/finish-phase-e.ps1 docs/tasks/phase-e-broaden-css.md
    if ($LASTEXITCODE -ne 0) { throw 'Staging failed' }
    git commit -m 'feat(ui): integrate native effects transitions and Phase E layout fixes'
}
$head = (git rev-parse HEAD).Trim()
Step 'Push PR branch' { git push origin HEAD:feat/phase-e-broaden-css }

$body = @'
Integrates the Phase E native layout, paint and motion paths and fixes the gaps
found during review: global z-index sorting, incorrect minmax/fr sizing and
column placement, transform-only hit geometry, two-stop gradient approximations,
fake shadow blur, missing subtree clipping/opacity and unwired transition helpers.

Also repairs Phase D's native multiline compilation error and optional CSS
transport, adds shared Windows text shaping, official Unicode grapheme fixtures,
focus/scroll integration fixes, cached effect textures and pinned QuickJS setup.

Validation: `pnpm test`, `pnpm run build:ui`, `zig build test`, `zig build
test-native`, `zig build`, and the actual bundled Solid/QuickJS application smoke
test all pass. Native checks use real OpenGL framebuffer pixels; core tests
include the three previously failing review reproductions.

See `docs/tasks/phase-e-broaden-css.md` for scope and limitations. This does not
certify 100% Chrome/Baseline or WPT conformance. The broader CSS catalog remains
open; no issue is automatically closed by this PR.
'@
$bodyPath = Join-Path $env:TEMP 'phase-e-pr-313-body.md'
[IO.File]::WriteAllText($bodyPath, $body, $utf8)
Step 'Update PR scope and verification' { gh pr edit 313 --repo RoboXGamer/SolidNativeZigExperiment --title 'feat(ui): integrate Phase E layout, native effects and transitions' --body-file $bodyPath }
$pr = gh pr view 313 --repo RoboXGamer/SolidNativeZigExperiment --json headRefOid,mergeable,mergeStateStatus,state,statusCheckRollup | ConvertFrom-Json
if ($pr.headRefOid -ne $head -or $pr.state -ne 'OPEN' -or $pr.mergeable -ne 'MERGEABLE') { throw 'PR head or merge state changed; stopping before merge.' }
if (@($pr.statusCheckRollup | Where-Object { $_.status -ne 'COMPLETED' -or $_.conclusion -notin @('SUCCESS','SKIPPED','NEUTRAL') }).Count) { throw 'Remote checks are pending or failed; stopping before merge.' }
Step 'Merge verified PR head' { gh pr merge 313 --repo RoboXGamer/SolidNativeZigExperiment --merge --match-head-commit $head }
Step 'Verify merged remote state' { gh pr view 313 --repo RoboXGamer/SolidNativeZigExperiment --json state,mergedAt,mergeCommit,url }
Write-Host "Verified and merged PR #313, head $head" -ForegroundColor Green
