$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force .deps | Out-Null
    $pin='589bc4120f2097fb1b135e552c2ef39f6581612b'
    if(!(Test-Path .deps/thorvg/.git)) {
        git clone --depth 1 --branch v1.1.3 https://github.com/thorvg/thorvg.git .deps/thorvg
        if($LASTEXITCODE) { throw 'ThorVG clone failed' }
    }
    if((git -C .deps/thorvg rev-parse HEAD).Trim() -ne $pin) { throw 'Unexpected ThorVG revision' }
    if(git -C .deps/thorvg status --porcelain) { throw 'ThorVG source has changes' }
    if(!(Test-Path .deps/glfw.zip)) { Invoke-WebRequest https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.bin.WIN64.zip -OutFile .deps/glfw.zip }
    if((Get-FileHash .deps/glfw.zip).Hash -ne '54EFA829400F2A0537F742B2B3BDD74E437BB4F2F048E4B7D3C5557D11A611E6') { throw 'GLFW archive hash mismatch' }
    if(!(Test-Path .deps/glfw-3.4.bin.WIN64)) { Expand-Archive -LiteralPath .deps/glfw.zip -DestinationPath .deps }
    if(!(Test-Path .build/tvg/build.ninja)) {
        uv tool run --from meson==1.12.1 meson setup .build/tvg .deps/thorvg --native-file zig-native.ini --default-library static '-Dengines=cpu,gl' -Dloaders=ttf -Dbindings=capi '-Dextra=' -Dsimd=false -Dthreads=true -Dstatic=true
        if($LASTEXITCODE) { throw 'Meson setup failed' }
    }
    ninja -C .build/tvg -j 6
    if($LASTEXITCODE) { throw 'ThorVG build failed' }
} finally { Pop-Location }
