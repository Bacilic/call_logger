# Μέτρηση χρόνου κλεισίματος call_logger.exe (ολόκληρη διεργασία, όχι μόνο Dart).
# Προαιρετικά: Process Monitor (Sysinternals) από CloseMainWindow μέχρι exit.
#
# Το log γράφεται στο: <φάκελος exe>\logs\shutdown_measure_<timestamp>.txt
# Procmon: procmon_shutdown_<timestamp>.pml / .csv / _summary.txt
#
# Χρήση:
#   pwsh -File scripts/measure_shutdown.ps1
#   pwsh -File scripts/measure_shutdown.ps1 -Method ForceKill
#   pwsh -File scripts/measure_shutdown.ps1 -SkipProcmon
#   pwsh -File scripts/measure_shutdown.ps1 -ProcmonPath "D:\Tools\Procmon64.exe"
#   pwsh -File scripts/measure_shutdown.ps1 -RegenerateProcmonSummary -ProcmonCsvPath "...\procmon_shutdown_*.csv" -WindowStart "2026-05-19 18:11:36.578" -WindowEnd "2026-05-19 18:11:53.131"

param(
    [string] $ExePath = '',
    [ValidateSet('CloseMainWindow', 'ForceKill')]
    [string] $Method = 'CloseMainWindow',
    [int] $WarmupSeconds = 4,
    [int] $TimeoutSeconds = 120,
    [int] $PollIntervalMs = 50,
    [switch] $SkipProcmon,
    [string] $ProcmonPath = 'C:\Users\Bacilic\Downloads\ProcessMonitor\Procmon64.exe',
    [switch] $RegenerateProcmonSummary,
    [string] $ProcmonCsvPath = '',
    [string] $WindowStart = '',
    [string] $WindowEnd = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = Join-Path $projectRoot 'build\windows\x64\runner\Release\call_logger.exe'
}

$ExePath = (Resolve-Path -LiteralPath $ExePath).Path
$exeDir = Split-Path -Parent $ExePath
$logsDir = Join-Path $exeDir 'logs'
$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$measureLog = Join-Path $logsDir ('shutdown_measure_' + $runStamp + '.txt')
$dartLog = Join-Path $logsDir 'shutdown_profile.log'
$procmonPml = Join-Path $logsDir ('procmon_shutdown_' + $runStamp + '.pml')
$procmonCsv = Join-Path $logsDir ('procmon_shutdown_' + $runStamp + '.csv')
$procmonSummary = Join-Path $logsDir ('procmon_shutdown_' + $runStamp + '_summary.txt')
$procmonFilterPmf = Join-Path $PSScriptRoot 'procmon_call_logger.pmf'

function Write-MeasureLog {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = $ts + ' | ' + $Message
    Write-Host $line
    Add-Content -LiteralPath $measureLog -Value $line -Encoding UTF8
}

function Write-PhaseLog {
    param([Parameter(Mandatory)][string[]]$Segments)
    Write-MeasureLog ($Segments -join ' | ')
}

function Get-ProcessInfoLine {
    param([System.Diagnostics.Process]$P)
    if ($null -eq $P -or $P.HasExited) { return 'n/a' }
    try {
        $P.Refresh()
        $memMb = [math]::Round($P.WorkingSet64 / 1MB, 1)
        $cpu = [math]::Round($P.TotalProcessorTime.TotalSeconds, 2)
        return ('pid={0} cpu_s={1} ws_mb={2}' -f $P.Id, $cpu, $memMb)
    } catch {
        return ('pid={0}' -f $P.Id)
    }
}

function Find-ProcmonExecutable {
    param([string]$ExplicitPath)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath) { return (Resolve-Path -LiteralPath $ExplicitPath).Path }
        throw "ProcmonPath not found: $ExplicitPath"
    }
    $candidates = @(
        'C:\Users\Bacilic\Downloads\ProcessMonitor\Procmon64.exe'
        (Join-Path ${env:ProgramFiles} 'Sysinternals\Procmon64.exe')
        (Join-Path ${env:ProgramFiles} 'Sysinternals Suite\Procmon64.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Sysinternals\Procmon64.exe')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\Procmon64.exe')
    )
    $cmd = Get-Command Procmon64.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Stop-ProcmonCapture {
    param([string]$ProcmonExe)
    if ([string]::IsNullOrWhiteSpace($ProcmonExe)) { return }
    try {
        Start-Process -FilePath $ProcmonExe -ArgumentList @('/AcceptEula', '/Terminate') -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
    } catch { }
    Start-Sleep -Milliseconds 800
    Get-Process -Name Procmon64, Procmon -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill() } catch { }
    }
    Start-Sleep -Milliseconds 400
}

function Start-ProcmonCapture {
    param(
        [string]$ProcmonExe,
        [string]$BackingPml,
        [int]$RuntimeSeconds
    )
    Stop-ProcmonCapture -ProcmonExe $ProcmonExe
    if (Test-Path -LiteralPath $BackingPml) {
        Remove-Item -LiteralPath $BackingPml -Force -ErrorAction SilentlyContinue
    }
    $args = @(
        '/AcceptEula'
        '/Quiet'
        '/Minimized'
        '/BackingFile'
        $BackingPml
        '/Runtime'
        [string]$RuntimeSeconds
    )
    Write-MeasureLog ('procmon | start | backing=' + $BackingPml + ' | runtime_s=' + $RuntimeSeconds)
    $null = Start-Process -FilePath $ProcmonExe -ArgumentList $args -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
}

function ConvertFrom-ProcmonTimeOfDay {
    param([string]$Value)
    # Procmon CSV (el-GR): "6:11:42,7291891 μμ" — ώρα μόνο, κόμμα στα κλασματικά δευτερόλεπτα.
    $v = ($Value + '').Trim().Trim('"')
    if ($v.Length -eq 0) { return $null }

    $isPm = $v -match '(μμ|μ\.μ\.)\s*$'
    $isAm = $v -match '(πμ|π\.μ\.)\s*$'
    if ($v -match '(?i)(PM)\s*$') { $isPm = $true }
    if ($v -match '(?i)(AM)\s*$') { $isAm = $true }

    $v = $v -replace '\s*(μμ|πμ|μ\.μ\.|π\.μ\.)\s*$', ''
    $v = $v -replace '\s*(?i)(AM|PM)\s*$', ''
    $v = $v.Trim() -replace ',', '.'

    if ($v -match '^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d+))?$') {
        $hour = [int]$Matches[1]
        $minute = [int]$Matches[2]
        $second = [int]$Matches[3]
        if ($isPm -and $hour -lt 12) { $hour += 12 }
        elseif ($isAm -and $hour -eq 12) { $hour = 0 }
        return [TimeSpan]::new($hour, $minute, $second)
    }

    [datetime]$parsed = [datetime]::MinValue
    $culture = [System.Globalization.CultureInfo]::CurrentCulture
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    if ([datetime]::TryParse($v, $culture, $styles, [ref]$parsed)) {
        return $parsed.TimeOfDay
    }
    return $null
}

function Test-InProcmonTimeWindow {
    param(
        [TimeSpan]$EventTime,
        [datetime]$WindowStart,
        [datetime]$WindowEnd
    )
    $margin = [TimeSpan]::FromMilliseconds(50)
    $start = $WindowStart.TimeOfDay - $margin
    $end = $WindowEnd.TimeOfDay + $margin
    if ($end -ge $start) {
        return ($EventTime -ge $start) -and ($EventTime -le $end)
    }
    return ($EventTime -ge $start) -or ($EventTime -le $end)
}

function Export-ProcmonPmlToCsv {
    param(
        [string]$ProcmonExe,
        [string]$PmlPath,
        [string]$CsvPath
    )
    if (-not (Test-Path -LiteralPath $PmlPath)) {
        Write-MeasureLog 'procmon | export | SKIP | PML missing'
        return $false
    }
    if (Test-Path -LiteralPath $CsvPath) {
        Remove-Item -LiteralPath $CsvPath -Force -ErrorAction SilentlyContinue
    }
    $args = @(
        '/AcceptEula'
        '/Quiet'
        '/OpenLog'
        $PmlPath
        '/SaveAs'
        $CsvPath
    )
    Write-MeasureLog ('procmon | export | begin | csv=' + $CsvPath)
    $p = Start-Process -FilePath $ProcmonExe -ArgumentList $args -WindowStyle Hidden -PassThru -Wait
    if (-not (Test-Path -LiteralPath $CsvPath)) {
        Write-MeasureLog ('procmon | export | FAIL | exit=' + $p.ExitCode)
        return $false
    }
    Write-MeasureLog ('procmon | export | OK | bytes=' + (Get-Item -LiteralPath $CsvPath).Length)
    return $true
}

function Write-ProcmonShutdownSummary {
    param(
        [string]$CsvPath,
        [string]$SummaryPath,
        [datetime]$WindowStart,
        [datetime]$WindowEnd,
        [string]$ProcessName = 'call_logger.exe'
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $null = $lines.Add('=== Procmon shutdown summary ===')
    $null = $lines.Add(('window_local: {0:yyyy-MM-dd HH:mm:ss.fff} -> {1:yyyy-MM-dd HH:mm:ss.fff}' -f $WindowStart, $WindowEnd))
    $null = $lines.Add(('process_filter: {0}' -f $ProcessName))
    $null = $lines.Add(('csv: {0}' -f $CsvPath))

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        $null = $lines.Add('ERROR: CSV not found')
        $lines | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
        return
    }

    Write-MeasureLog ('procmon | summary | loading CSV (may take a while)...')
    $allRows = @(Import-Csv -LiteralPath $CsvPath)
    $null = $lines.Add(('csv_total_rows: {0}' -f $allRows.Count))

    $byProcess = @($allRows | Where-Object { $_.'Process Name' -eq $ProcessName })
    $null = $lines.Add(('rows_process_{0}: {1}' -f $ProcessName, $byProcess.Count))

    $filtered = foreach ($r in $byProcess) {
        $tod = ConvertFrom-ProcmonTimeOfDay -Value $r.'Time of Day'
        if ($null -eq $tod) { continue }
        if (-not (Test-InProcmonTimeWindow -EventTime $tod -WindowStart $WindowStart -WindowEnd $WindowEnd)) {
            continue
        }
        $r
    }
    $filtered = @($filtered)
    $null = $lines.Add(('window_rows ({0}): {1}' -f $ProcessName, $filtered.Count))

    if ($filtered.Count -eq 0) {
        $null = $lines.Add('No events in window (check Time of Day column / locale).')
        $lines | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
        return
    }

    $null = $lines.Add('')
    $null = $lines.Add('--- Events by Operation (top 25) ---')
    $filtered |
        Group-Object -Property Operation |
        Sort-Object -Property Count -Descending |
        Select-Object -First 25 |
        ForEach-Object { $null = $lines.Add(('{0,8}  {1}' -f $_.Count, $_.Name)) }

    $ioOps = @(
        'ReadFile', 'WriteFile', 'CreateFile', 'CloseFile', 'SetDispositionInformationFile',
        'QueryDirectory', 'FlushBuffersFile', 'CreateFileMapping', 'MapViewOfFile'
    )
    $null = $lines.Add('')
    $null = $lines.Add('--- Top paths (file I/O ops, top 30) ---')
    $filtered |
        Where-Object { $ioOps -contains $_.Operation } |
        Group-Object -Property Path |
        Sort-Object -Property Count -Descending |
        Select-Object -First 30 |
        ForEach-Object { $null = $lines.Add(('{0,6}  {1}' -f $_.Count, $_.Name)) }

    $null = $lines.Add('')
    $null = $lines.Add('--- Registry (top 20 paths) ---')
    $filtered |
        Where-Object { $_.Operation -like 'Reg*' } |
        Group-Object -Property Path |
        Sort-Object -Property Count -Descending |
        Select-Object -First 20 |
        ForEach-Object { $null = $lines.Add(('{0,6}  {1}' -f $_.Count, $_.Name)) }

    $null = $lines.Add('')
    $null = $lines.Add('--- Non-SUCCESS (top 30) ---')
    $filtered |
        Where-Object { $_.Result -and $_.Result -ne 'SUCCESS' } |
        Select-Object -First 30 |
        ForEach-Object {
            $null = $lines.Add(
                ('{0} | {1} | {2} | {3}' -f $_.'Time of Day', $_.Operation, $_.Result, $_.Path)
            )
        }

    $null = $lines.Add('')
    $null = $lines.Add('--- Timeline (first 40 events in window) ---')
    $filtered |
        Select-Object -First 40 |
        ForEach-Object {
            $null = $lines.Add(
                ('{0} | {1} | {2} | {3}' -f $_.'Time of Day', $_.Operation, $_.Result, $_.Path)
            )
        }

    $lines | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

# --- Αναδημιουργία σύνοψης από υπάρχον CSV (χωρίς εκτέλεση εφαρμογής) ---
if ($RegenerateProcmonSummary) {
    if ([string]::IsNullOrWhiteSpace($ProcmonCsvPath)) {
        throw 'RegenerateProcmonSummary requires -ProcmonCsvPath'
    }
    if ([string]::IsNullOrWhiteSpace($WindowStart) -or [string]::IsNullOrWhiteSpace($WindowEnd)) {
        throw 'RegenerateProcmonSummary requires -WindowStart and -WindowEnd (from shutdown_measure log: procmon | window_*)'
    }
    $csvResolved = (Resolve-Path -LiteralPath $ProcmonCsvPath).Path
    $summaryPath = $csvResolved -replace '\.csv$', '_summary.txt'
    $measureLog = Join-Path (Split-Path $csvResolved) ('shutdown_measure_regen_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $ws = [datetime]::Parse($WindowStart, [System.Globalization.CultureInfo]::CurrentCulture)
    $we = [datetime]::Parse($WindowEnd, [System.Globalization.CultureInfo]::CurrentCulture)
    Write-MeasureLog '=== Regenerate Procmon summary ==='
    Write-ProcmonShutdownSummary -CsvPath $csvResolved -SummaryPath $summaryPath -WindowStart $ws -WindowEnd $we
    Write-Host ('Summary: ' + $summaryPath)
    exit 0
}

# --- Main ---
Write-MeasureLog '=== Metrisi kleisimatos call_logger ==='
Write-MeasureLog ('exe: ' + $ExePath)
Write-MeasureLog ('working_dir: ' + $exeDir)
Write-MeasureLog ('method: ' + $Method)
Write-PhaseLog @(
    'config'
    ('warmup_s=' + $WarmupSeconds)
    ('timeout_s=' + $TimeoutSeconds)
    ('poll_ms=' + $PollIntervalMs)
    ('procmon=' + (-not $SkipProcmon))
)
Write-MeasureLog ('measure_log: ' + $measureLog)
Write-MeasureLog ('dart_log: ' + $dartLog)

$procmonExe = $null
$procmonEnabled = $false
if (-not $SkipProcmon) {
    if ($Method -ne 'CloseMainWindow') {
        Write-MeasureLog 'procmon | SKIP | only enabled for CloseMainWindow (use -SkipProcmon to disable)'
    } else {
        $procmonExe = Find-ProcmonExecutable -ExplicitPath $ProcmonPath
        if ($null -eq $procmonExe) {
            Write-MeasureLog 'procmon | SKIP | Procmon64.exe not found (install Sysinternals Process Monitor)'
            Write-MeasureLog 'procmon | hint | https://learn.microsoft.com/sysinternals/downloads/procmon'
        } else {
            $procmonEnabled = $true
            Write-MeasureLog ('procmon | exe: ' + $procmonExe)
            Write-MeasureLog ('procmon | pml: ' + $procmonPml)
            Write-MeasureLog ('procmon | csv: ' + $procmonCsv)
            Write-MeasureLog ('procmon | summary: ' + $procmonSummary)
        }
    }
}

$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

Write-PhaseLog @('PHASE', 'start_process', 'begin')
$proc = Start-Process -FilePath $ExePath -WorkingDirectory $exeDir -PassThru
Write-PhaseLog @(
    'PHASE', 'start_process', 'end'
    ('elapsed_ms=' + $swTotal.ElapsedMilliseconds)
    (Get-ProcessInfoLine $proc)
)

Write-PhaseLog @('PHASE', 'warmup', 'begin', ('target_s=' + $WarmupSeconds))
for ($i = 1; $i -le $WarmupSeconds; $i++) {
    Start-Sleep -Seconds 1
    $alive = $true
    try {
        $null = Get-Process -Id $proc.Id -ErrorAction Stop
    } catch {
        $alive = $false
    }
    if (-not $alive) {
        Write-PhaseLog @(
            'PHASE', 'warmup', 'abort', 'process_exited_early'
            ('after_s=' + $i)
            ('elapsed_ms=' + $swTotal.ElapsedMilliseconds)
        )
        Write-MeasureLog 'RESULT | FAIL | process died before warmup finished'
        exit 1
    }
    Write-PhaseLog @(
        'PHASE', 'warmup', 'tick'
        ('second=' + $i + '/' + $WarmupSeconds)
        ('elapsed_ms=' + $swTotal.ElapsedMilliseconds)
        (Get-ProcessInfoLine $proc)
    )
}
Write-PhaseLog @('PHASE', 'warmup', 'end', ('elapsed_ms=' + $swTotal.ElapsedMilliseconds))

Write-PhaseLog @('PHASE', 'shutdown_signal', 'begin')
$swClose = [System.Diagnostics.Stopwatch]::StartNew()
$shutdownSignalTime = Get-Date
$procmonRuntimeSec = [math]::Min($TimeoutSeconds + 15, 180)

if ($procmonEnabled) {
    Start-ProcmonCapture -ProcmonExe $procmonExe -BackingPml $procmonPml -RuntimeSeconds $procmonRuntimeSec
    Write-MeasureLog ('procmon | window_start (CloseMainWindow): ' + $shutdownSignalTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))
}

switch ($Method) {
    'CloseMainWindow' {
        $sent = $proc.CloseMainWindow()
        Write-PhaseLog @(
            'PHASE', 'shutdown_signal', 'CloseMainWindow'
            ('sent=' + $sent)
            ('elapsed_ms=' + $swTotal.ElapsedMilliseconds)
            (Get-ProcessInfoLine $proc)
        )
        if (-not $sent) {
            Write-MeasureLog 'WARN | CloseMainWindow returned false (no main window or not ready)'
        }
    }
    'ForceKill' {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Write-PhaseLog @(
            'PHASE', 'shutdown_signal', 'ForceKill'
            ('elapsed_ms=' + $swTotal.ElapsedMilliseconds)
        )
    }
}
Write-PhaseLog @('PHASE', 'shutdown_signal', 'end', ('signal_ms=' + $swClose.ElapsedMilliseconds))

Write-PhaseLog @('PHASE', 'wait_process_exit', 'begin')
$pollIndex = 0
$deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
$exited = $false
$lastPollMs = 0
$processGoneTime = $null

while ([datetime]::UtcNow -lt $deadline) {
    $pollIndex++
    $alive = $true
    try {
        $null = Get-Process -Id $proc.Id -ErrorAction Stop
    } catch {
        $alive = $false
    }

    if (-not $alive) {
        $exited = $true
        $processGoneTime = Get-Date
        Write-PhaseLog @(
            'PHASE', 'wait_process_exit', 'process_gone'
            ('poll=' + $pollIndex)
            ('since_signal_ms=' + $swClose.ElapsedMilliseconds)
            ('session_ms=' + $swTotal.ElapsedMilliseconds)
        )
        break
    }

    $sinceSignal = $swClose.ElapsedMilliseconds
    $shouldLog = ($pollIndex -le 10) -or (($sinceSignal - $lastPollMs) -ge 500)
    if ($shouldLog) {
        Write-PhaseLog @(
            'PHASE', 'wait_process_exit', 'poll'
            ('n=' + $pollIndex)
            ('since_signal_ms=' + $sinceSignal)
            ('session_ms=' + $swTotal.ElapsedMilliseconds)
            (Get-ProcessInfoLine $proc)
        )
        $lastPollMs = $sinceSignal
    }

    Start-Sleep -Milliseconds $PollIntervalMs
}

$swClose.Stop()
$swTotal.Stop()

if (-not $exited) {
    $processGoneTime = Get-Date
    Write-PhaseLog @(
        'PHASE', 'wait_process_exit', 'TIMEOUT'
        ('after_s=' + $TimeoutSeconds)
        ('since_signal_ms=' + $swClose.ElapsedMilliseconds)
    )
    Write-MeasureLog 'RESULT | FAIL | process still running'
}

Write-PhaseLog @('PHASE', 'wait_process_exit', 'end', ('polls=' + $pollIndex))

if ($procmonEnabled) {
    if ($null -eq $processGoneTime) { $processGoneTime = Get-Date }
    Write-MeasureLog ('procmon | window_end (process_gone/timeout): ' + $processGoneTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))
    Stop-ProcmonCapture -ProcmonExe $procmonExe
    $exported = Export-ProcmonPmlToCsv -ProcmonExe $procmonExe -PmlPath $procmonPml -CsvPath $procmonCsv
    if ($exported) {
        Write-ProcmonShutdownSummary `
            -CsvPath $procmonCsv `
            -SummaryPath $procmonSummary `
            -WindowStart $shutdownSignalTime `
            -WindowEnd $processGoneTime
        Write-MeasureLog ('procmon | summary_written: ' + $procmonSummary)
    }
}

Write-MeasureLog '--- SUMMARY ---'
Write-MeasureLog ('signal_to_process_gone_ms: ' + $swClose.ElapsedMilliseconds)
Write-MeasureLog ('start_to_process_gone_ms: ' + $swTotal.ElapsedMilliseconds)
Write-MeasureLog ('warmup_config_s: ' + $WarmupSeconds)
if ($exited) {
    Write-MeasureLog 'RESULT | OK'
} else {
    Write-MeasureLog 'RESULT | FAIL | timeout'
}

if (Test-Path -LiteralPath $dartLog) {
    Write-MeasureLog '--- tail shutdown_profile.log (Dart) ---'
    Get-Content -LiteralPath $dartLog -Tail 30 -ErrorAction SilentlyContinue | ForEach-Object {
        Write-MeasureLog ('  dart | ' + $_)
    }
} else {
    Write-MeasureLog '--- shutdown_profile.log not found ---'
}

Write-MeasureLog '=== END ==='

Write-Host ''
Write-Host ('Process shutdown (signal -> exit): ' + $swClose.ElapsedMilliseconds + ' ms') -ForegroundColor Cyan
Write-Host ('Total (start -> exit): ' + $swTotal.ElapsedMilliseconds + ' ms') -ForegroundColor Cyan
Write-Host ('Log: ' + $measureLog)
if ($procmonEnabled -and (Test-Path -LiteralPath $procmonSummary)) {
    Write-Host ('Procmon summary: ' + $procmonSummary) -ForegroundColor Yellow
}

if (-not $exited) { exit 2 }
