param([Parameter(Mandatory=$true)][string]$Path, [ValidateSet('None','Read')][string]$Share = 'None')
$stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::$Share)
try {
    [Console]::WriteLine('LOCKED')
    [Console]::Out.Flush()
    [Console]::ReadLine() | Out-Null
} finally { $stream.Dispose() }
