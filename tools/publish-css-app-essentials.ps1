$ErrorActionPreference='Stop'
Set-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
function Native([scriptblock]$Command) {& $Command; if($LASTEXITCODE -ne 0){throw "Publishing stopped: exit $LASTEXITCODE"}}
if((git branch --show-current).Trim() -ne 'feat/css-app-essentials'){throw 'Unexpected branch'}
# No builds/tests/typechecks: validation remains paused by explicit user request.
Native {git add README.md build.zig modules/ui_core/layout_block.zig modules/ui_core/layout_flex.zig modules/ui_core/paint.zig modules/ui_core/interaction.zig modules/ui_core/root.zig modules/ui_core/scene.zig modules/ui_core/style.zig modules/ui_core/text.zig modules/ui_core/text_edit.zig packages/solid-zig/src/native.d.ts packages/solid-zig/src/native.js src/renderer.zig src/shaders/clip.fs src/text_backend.c src/text_backend.zig src/cursor_backend.c src/windows.zig docs/audit/css-app-essentials.json docs/tasks/css-app-essentials-2026-11-12.md tools/publish-css-app-essentials.ps1}
Native {git commit -m 'feat(ui): add common app typography box visuals and interaction styling'}
Native {git push -u origin feat/css-app-essentials}
$body=@'
Groups everyday app typography/text and box/interaction features into two
parallel implementation tracks, with shared JSX/native consumer integration.

Native font stacks/weight/style, glyph spacing/tab stops, shaped overflow and
indentation, elliptical corners, outline styles, visibility/pointer policy and
cached cursor resources now have concrete native paths. The exact ticket scopes
and partial behaviors are in docs/audit/css-app-essentials.json and
docs/tasks/css-app-essentials-2026-11-12.md.

Validation is explicitly paused by the user: no builds, tests, typechecks or
browser comparisons ran. Closures mean implementation delivery, unverified.
The broader font-face, text fragmentation/RTL, SVG and resource/network gaps
remain open and are named in the handoff. This is not an 80% conformance claim.

Fixes #94.
Fixes #95.
Fixes #147.
Fixes #285.
Fixes #241.
Fixes #25.
Fixes #180.
Fixes #181.
'@
$path=Join-Path $env:TEMP 'css-app-essentials-pr.md'
[IO.File]::WriteAllText($path,$body,(New-Object System.Text.UTF8Encoding($false)))
# Creation is last; link the returned PR as the next assistant tool call.
Native {gh pr create --repo RoboXGamer/SolidNativeZigExperiment --base master --head feat/css-app-essentials --title 'feat(ui): implement everyday app typography, box visuals and interaction' --body-file $path}
