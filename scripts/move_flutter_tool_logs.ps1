# Μεταφέρει flutter_*.log από τη ρίζα του project στον φάκελο logs/
# (το Flutter CLI τα γράφει στο cwd όταν κρασάρει το εργαλείο — δεν αλλάζει διαδρομή με flag).
#
# Usage:
#   pwsh -File scripts/move_flutter_tool_logs.ps1
#   pwsh -File scripts/move_flutter_tool_logs.ps1 -ProjectRoot "F:\path\to\call_logger"

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    exit 0
}

$logsDir = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$files = @(
    Get-ChildItem -LiteralPath $ProjectRoot -Filter 'flutter_*.log' -File -ErrorAction SilentlyContinue
)

foreach ($f in $files) {
    $dest = Join-Path $logsDir $f.Name
    if (Test-Path -LiteralPath $dest) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $dest = Join-Path $logsDir "${base}_${stamp}.log"
    }
    try {
        Move-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    catch {
        # Αν το αρχείο είναι κλειδωμένο, αγνοούμε — θα ξαναπροσπαθήσει στην επόμενη εκτέλεση.
    }
}

exit 0
