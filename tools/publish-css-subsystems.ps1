param([switch]$Publish)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repo
$encoding=New-Object System.Text.UTF8Encoding($false)
function Save([string]$Path,[string]$Text) {[IO.File]::WriteAllText((Join-Path $repo $Path),$Text,$encoding)}
function Native([scriptblock]$Command) { & $Command; if($LASTEXITCODE -ne 0){throw "Command failed ($LASTEXITCODE); publishing stopped."} }

# One subsystem batch, with frozen ticket denominators. Tests/builds are paused.
$groups=@(
    @{number=232;id='static-positioning';year=2024;owner='modules/ui_core/scene.zig'},
    @{number=179;id='opacity';year=2024;owner='packages/solid-zig/src/native.js; modules/ui_core/scene.zig; src/renderer.zig'},
    @{number=143;id='isolation';year=2024;owner='modules/ui_core/scene.zig; src/renderer.zig'},
    @{number=63;id='cubic-bezier-easing';year=2024;owner='modules/ui_core/animation.zig; modules/ui_core/transitions.zig'},
    @{number=233;id='steps-easing';year=2024;owner='modules/ui_core/animation.zig; modules/ui_core/transitions.zig'},
    @{number=152;id='linear-easing';year=2024;owner='modules/ui_core/animation.zig; modules/ui_core/transitions.zig'},
    @{number=289;id='abs-sign';year=2025;owner='modules/ui_core/sizing.zig; modules/ui_core/css_math.zig'},
    @{number=30;id='calc-constants';year=2024;owner='modules/ui_core/sizing.zig; modules/ui_core/css_math.zig'},
    @{number=267;id='trig-functions';year=2024;owner='modules/ui_core/sizing.zig; modules/ui_core/css_math.zig'},
    @{number=80;id='exp-functions';year=2024;owner='modules/ui_core/sizing.zig; modules/ui_core/css_math.zig'},
    @{number=215;id='round-mod-rem';year=2024;owner='modules/ui_core/sizing.zig; modules/ui_core/css_math.zig'},
    @{number=169;id='named-color';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=212;id='rgb';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=127;id='hsl';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=128;id='hwb';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=144;id='lab';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=178;id='oklab';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=41;id='color-function';year=2024;owner='modules/ui_core/colors.zig'},
    @{number=293;id='conic-gradients';year=2025;owner='modules/ui_core/gradient.zig; src/renderer.zig'},
    @{number=297;id='gradients';year=2025;owner='modules/ui_core/gradient.zig; src/renderer.zig'}
)
$catalog2024=Get-Content docs/issues/manifest.json -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog2025=Get-Content docs/issues-2025/manifest.json -Raw -Encoding UTF8 | ConvertFrom-Json
$entries=foreach($group in $groups) {
    $catalog=if($group.year -eq 2024){$catalog2024}else{$catalog2025}
    $issue=$catalog.issues | Where-Object id -eq $group.id
    if(-not $issue){throw "Missing pinned catalog entry: $($group.id)"}
    $keys=@([regex]::Matches($issue.body,'`(css\.[^`]+)`') | ForEach-Object {$_.Groups[1].Value} | Sort-Object -Unique)
    [ordered]@{issue=$group.number;feature=$group.id;baseline=$group.year;compatibilityKeys=$keys;implementationOwner=$group.owner;status=$(if($group.number -in @(41,144,178)){'partial-unverified'}else{'implemented-unverified'});validation='Not run: user explicitly paused builds and tests';browserConformance='Not certified'}
}
Save 'docs/audit/css-subsystem-batch.json' (([ordered]@{date='2026-11-12';scope='native Solid/Zig consumer paths';validationPaused=$true;issues=@($entries)} | ConvertTo-Json -Depth 8)+"`n")
$table=($entries | ForEach-Object {"| #$($_.issue) | $($_.feature) | $($_.compatibilityKeys.Count) | $($_.status) |"}) -join "`n"
$text=@'
# CSS subsystem batch — 2026-11-12

Implementation-only delivery. The user explicitly stopped all builds, tests,
typechecks and test authoring for this batch. No runtime, browser or test success
is claimed. Issue completion here means the native implementation has been
written; verification acceptance remains outstanding. This record supersedes
the historical source-only statuses for the listed native paths, not the global
Baseline conformance assessment.

The batch groups shared infrastructure rather than isolated ticket patches:

- Values/math: typed constants, sign, trigonometry, exponential and rounding
  families share the sizing parser. Raw typed results preserve nonfinite values
  and signed zero; final layout lengths retain safety validation. The scalar
  dimension model does not represent compound/inverse dimensions. Newer
  device-dependent line-width rounding is outside the pinned ticket scope.
- Colors/paint: one parser supplies named, RGB/HSL/HWB, Lab/LCH/Oklab/OKLCH and
  explicit color spaces to backgrounds, gradients, shadows, text and borders.
  The backend targets its existing 8-bit sRGB framebuffer; HDR/wide-gamut output,
  relative colors, color-mix(), CSS cascade and color-scheme queries are separate
  features. CurrentColor is resolved from inherited native computed styles.
- Easing/motion: validated cubic, stepped and piecewise-linear curves feed the
  retained transition timeline, including ownership, retarget and cancellation.
  This does not implement the separate CSS keyframe-animation family.
- Native integration: percentage/scientific opacity, isolated stacking contexts,
  ignored static insets and math-aware font/transform consumers. The retained
  Tree owns new CSS strings through its existing reflective cloning.

## Frozen ticket scopes

Lab/LCH, Oklab/OKLCH and color() tickets #144/#178/#41 remain open: their
parsers and conversion paths are written, but the framebuffer still clips
wide-gamut values instead of implementing perceptual gamut mapping.

The machine-readable companion lists each eligible compatibility key and its
implementation owner. Counts describe the catalog scope, not passed tests.

| Issue | Feature | Eligible keys | Status |
| --- | --- | --- | --- |
'@
Save 'docs/tasks/css-subsystem-batch-2026-11-12.md' ($text+"`n"+$table+"`n")

if(-not $Publish){Write-Host 'Wrote batch scope and implementation status; no builds/tests run.';exit 0}
$branch=(git branch --show-current).Trim()
if($branch -ne 'feat/css-small-batch'){throw 'Unexpected branch; refusing to publish'}
Native {git add modules/ui_core/css_syntax.zig modules/ui_core/animation.zig modules/ui_core/easing.zig modules/ui_core/transitions.zig modules/ui_core/sizing.zig modules/ui_core/css_math.zig modules/ui_core/colors.zig modules/ui_core/gradient.zig modules/ui_core/style.zig modules/ui_core/scene.zig modules/ui_core/transform.zig packages/solid-zig/src/native.js packages/solid-zig/src/native.d.ts src/windows.zig docs/audit/css-subsystem-batch.json docs/tasks/css-subsystem-batch-2026-11-12.md tools/publish-css-subsystems.ps1}
Native {git commit -m 'feat(css): implement grouped math colors easing and paint primitives'}
Native {git push -u origin feat/css-small-batch}
$body=@'
Implements a grouped native CSS values/math, color/paint and easing/motion batch.
Shared parsers and the native consumers are updated together; the exact pinned
ticket keys and implementation owners are in docs/audit/css-subsystem-batch.json.

Validation was explicitly paused by the user: no tests, builds or typechecks
were run. These issue closures record implementation delivery, not verified
browser/WPT conformance. Limitations and remaining compatibility work are listed
in docs/tasks/css-subsystem-batch-2026-11-12.md.

'@
$body+=($groups | Where-Object {$_.number -notin @(41,144,178)} | ForEach-Object {"Fixes #$($_.number)."}) -join "`n"
$bodyPath=Join-Path $env:TEMP 'css-subsystems-pr-body.md'
[IO.File]::WriteAllText($bodyPath,$body,$encoding)
# PR creation is last so the next assistant tool call can link it immediately.
Native {gh pr create --repo RoboXGamer/SolidNativeZigExperiment --base master --head feat/css-small-batch --title 'feat(css): group native math, colors, easing and paint primitives' --body-file $bodyPath}
