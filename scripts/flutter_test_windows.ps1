# Safe flutter test on Windows when native_assets copy fails with:
# PathExistsException / errno 183 (sqlite3.dll target already exists; Flutter copy may not replace).
#
# Usage:
#   pwsh -File scripts/flutter_test_windows.ps1
#   pwsh -File scripts/flutter_test_windows.ps1 test/call_form_test.dart
#   pwsh -File scripts/flutter_test_windows.ps1 -Clean   # runs flutter clean first (if DLL/folder is locked)

param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if ($Clean) {
    Write-Host 'Running flutter clean...'
    & flutter clean
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$dllPath = Join-Path $projectRoot 'build\native_assets\windows\sqlite3.dll'
$nativeWindowsDir = Join-Path $projectRoot 'build\native_assets\windows'

function Remove-PathWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$MaxAttempts = 12,
        [int]$DelayMs = 400
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            if (Test-Path -LiteralPath $Path -PathType Container) {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            }
            else {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            }
            return $true
        }
        catch {
            if ($i -eq $MaxAttempts) {
                Write-Warning @"
Could not remove: $Path
Close Flutter/Dart processes (running app, IDE test, second terminal), then retry or run: flutter clean
$($_.Exception.Message)
"@
                return $false
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    return $false
}

# Prefer removing only the DLL; if locked, remove the whole windows native_assets folder.
if (Test-Path -LiteralPath $dllPath) {
    $removed = Remove-PathWithRetry -Path $dllPath -MaxAttempts 8
    if (-not $removed) {
        if (-not (Remove-PathWithRetry -Path $nativeWindowsDir)) {
            Write-Warning 'Try: close all Flutter/Dart processes, then re-run this script, or use -Clean after closing them.'
            exit 1
        }
    }
}

$exitCode = 1
try {
    & flutter test @args
    $exitCode = $LASTEXITCODE
}
finally {
    & (Join-Path $PSScriptRoot 'move_flutter_tool_logs.ps1') -ProjectRoot $projectRoot
}
exit $exitCode
