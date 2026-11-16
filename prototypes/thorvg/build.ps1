param([switch]$Run,[switch]$View,[switch]$Check)
$ErrorActionPreference = 'Stop'
function Save-Log([string]$Name, $Lines) {
    [IO.File]::WriteAllLines((Join-Path (Get-Location) "artifacts/$Name"), [string[]]$Lines, [Text.UTF8Encoding]::new($false))
}
Push-Location $PSScriptRoot
try {
    & zig c++ -O3 -std=c++17 -DTVG_STATIC -I .deps/thorvg/inc -I .deps/glfw-3.4.bin.WIN64/include probe.cpp .build/tvg/src/libthorvg-1.a .deps/glfw-3.4.bin.WIN64/lib-mingw-w64/libglfw3dll.a -lopengl32 -lgdi32 -ld2d1 -ldwrite -lwindowscodecs -lole32 -luuid -o .build/probe.exe
    if($LASTEXITCODE) { throw 'Prototype compilation failed' }
    Copy-Item .deps/glfw-3.4.bin.WIN64/lib-mingw-w64/glfw3.dll .build/glfw3.dll -Force
    New-Item -ItemType Directory -Force artifacts | Out-Null
    if($Run) { & ./.build/probe.exe | Tee-Object -Variable runLines; Save-Log run.txt $runLines; if($LASTEXITCODE) { throw "Probe exited $LASTEXITCODE" } }
    if($Check) { & ./.build/probe.exe --check | Tee-Object -Variable checkLines; Save-Log checks.txt $checkLines; if($LASTEXITCODE) { throw "Checks exited $LASTEXITCODE" } }
    if($View) { & ./.build/probe.exe --view }
    & zig build-exe abi-smoke.zig -O ReleaseFast .build/tvg/src/libthorvg-1.a -lc -lc++ -lopengl32 '-femit-bin=.build/abi-smoke.exe'
    if($LASTEXITCODE) { throw 'Zig C ABI compilation failed' }
    & ./.build/abi-smoke.exe | Tee-Object -Variable abiLines
    Save-Log abi-smoke.txt $abiLines
    if($LASTEXITCODE) { throw 'Zig C ABI smoke failed' }
} finally { Pop-Location }
