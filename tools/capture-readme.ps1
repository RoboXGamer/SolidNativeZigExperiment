param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('counter', 'css', 'tictactoe')]
    [string]$Example
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
$previousScreenshot = [Environment]::GetEnvironmentVariable('SOLID_NATIVE_SCREENSHOT')
try {
    & pnpm build:ui --example $Example
    if ($LASTEXITCODE -ne 0) { throw "UI build failed for $Example" }
    & zig build
    if ($LASTEXITCODE -ne 0) { throw "Native build failed for $Example" }

    $captureDirectory = Join-Path $projectRoot 'zig-out/readme-captures'
    $imageDirectory = Join-Path $projectRoot 'docs/images'
    New-Item -ItemType Directory -Force $captureDirectory, $imageDirectory | Out-Null
    $rawPath = Join-Path $captureDirectory "$Example-raw.png"
    $outputPath = Join-Path $imageDirectory "$Example-native.png"
    $env:SOLID_NATIVE_SCREENSHOT = $rawPath

    # Invoke directly so stderr log records stay text in Windows PowerShell.
    $captureProcess = New-Object System.Diagnostics.Process
    $captureProcess.StartInfo.FileName = (Get-Command node).Source
    $captureProcess.StartInfo.Arguments = 'tools/smoke-native.mjs'
    $captureProcess.StartInfo.WorkingDirectory = $projectRoot
    $captureProcess.StartInfo.UseShellExecute = $false
    $captureProcess.StartInfo.CreateNoWindow = $true
    $captureProcess.StartInfo.RedirectStandardOutput = $true
    $captureProcess.StartInfo.RedirectStandardError = $true
    try {
        $null = $captureProcess.Start()
        $stdout = $captureProcess.StandardOutput.ReadToEndAsync()
        $stderr = $captureProcess.StandardError.ReadToEndAsync()
        $captureProcess.WaitForExit()
        $captureLog = $stdout.Result + $stderr.Result
        if ($captureProcess.ExitCode -ne 0) { throw $captureLog }
    } finally { $captureProcess.Dispose() }
    if ($captureLog -notmatch 'Render size:\s+(\d+) x (\d+)') {
        throw "Render dimensions missing from native output: $captureLog"
    }
    $renderWidth = [int]$Matches[1]
    $renderHeight = [int]$Matches[2]
    [System.IO.File]::WriteAllText((Join-Path $captureDirectory "$Example.log"), $captureLog)

    # At 125% DPI Raylib's screenshot includes unused black pixels above/right
    # of its logged render viewport. Copy that viewport without resampling.
    Add-Type -AssemblyName System.Drawing
    $rawImage = [System.Drawing.Bitmap]::FromFile($rawPath)
    try {
        if ($rawImage.Width -lt $renderWidth -or $rawImage.Height -lt $renderHeight) {
            throw 'Screenshot is smaller than the logged native render viewport'
        }
        $viewport = [System.Drawing.Rectangle]::new(0, $rawImage.Height - $renderHeight, $renderWidth, $renderHeight)
        $image = $rawImage.Clone($viewport, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try { $image.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $image.Dispose() }
    } finally { $rawImage.Dispose() }
    Write-Output "Saved $outputPath ($renderWidth x $renderHeight native viewport)"
} finally {
    [Environment]::SetEnvironmentVariable('SOLID_NATIVE_SCREENSHOT', $previousScreenshot)
    Pop-Location
}
