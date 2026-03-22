#requires -Version 5.1
<#
.SYNOPSIS
    Όταν υπάρχουν και το sqlite3.dll και ο φάκελος hooks sqlite3: τερματίζει αυτόματα dartvm.exe,
    ρωτά με αριθμό για κάθε άλλη διεργασία που φορτώνει το DLL, και διαγράφει τα δύο στόχους.
    Αν λείπει ένα από τα δύο, δεν τερματίζει διεργασίες (άσκοπο)· επιχειρεί μόνο διαγραφές όπου υπάρχουν αρχεία.

.DESCRIPTION
    Λόγος: Κατά την εκτέλεση ελέγχων (flutter test / native assets) το sqlite3.dll και ο φάκελος hooks
    συχνά παραμένουν κλειδωμένα· χωρίς καθάρισμα οδηγεί σε PathExistsException και ανάγκη επανεκκίνησης.

    Ο τερματισμός διεργασιών γίνεται μόνο αν υπάρχουν και τα δύο στόχοι (για να μην κλείνει άσκοπα dartvm).
    Οι dartvm.exe τότε τερματίζονται αυτόματα (επαναλήψεις / poll). Καμία άλλη διεργασία δεν κλείνει
    χωρίς ρητή επιλογή αριθμού.

.NOTES
    Εκτέλεση από τερματικό Cursor (pwsh), με cwd τη ρίζα του project:
        pwsh -NoProfile -File .\scripts\terminate_dartvm_delete_sqlite3_dll.ps1

    Προαιρετικά: -DryRun (χωρίς τερματισμό / χωρίς διαγραφή, μόνο μηνύματα)
#>
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
}
catch {
    # Αγνοούμε αν δεν υπάρχει κονσόλα (π.χ. ορισμένα hosted περιβάλλοντα).
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$dllPath = Join-Path $projectRoot 'build\native_assets\windows\sqlite3.dll'
$hooksDir = Join-Path $projectRoot '.dart_tool\hooks_runner\sqlite3'

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ΣΦΑΛΜΑ] $Message" -ForegroundColor Red
}

function Test-IsAdministrator {
    $p = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Read-NumericChoice {
    param(
        [string]$Prompt,
        [int]$Min,
        [int]$Max
    )
    while ($true) {
        $raw = Read-Host $Prompt
        if ($null -eq $raw) { continue }
        $t = $raw.Trim()
        if ($t -notmatch '^\d+$') {
            Write-Err "Δώστε ακέραιο μεταξύ $Min και $Max."
            continue
        }
        $n = [int]$t
        if ($n -lt $Min -or $n -gt $Max) {
            Write-Err "Εκτός εύρους. Επιτρέπονται: $Min-$Max."
            continue
        }
        return $n
    }
}

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
                Write-Err @"
Αδυναμία διαγραφής: $Path
Κλείστε διεργασίες που κρατούν το αρχείο/φάκελο και ξανατρέξτε το script.
$($_.Exception.Message)
"@
                return $false
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    return $false
}

function Get-FullPathNormalized {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return $null
    }
    return [System.IO.Path]::GetFullPath((Get-Item -LiteralPath $LiteralPath).FullName)
}

function Get-ProcessesLoadingDll {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DllFullPath
    )

    $seen = @{}
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        try {
            foreach ($m in @($proc.Modules)) {
                if ([string]::IsNullOrEmpty($m.FileName)) { continue }
                try {
                    $mf = [System.IO.Path]::GetFullPath($m.FileName)
                }
                catch {
                    continue
                }
                if ([string]::Equals($mf, $DllFullPath, [StringComparison]::OrdinalIgnoreCase)) {
                    $seen[$proc.Id] = $proc
                    break
                }
            }
        }
        catch {
            # Πρόσβαση σε modules συστήματος / προστατευμένων διεργασιών.
        }
    }
    return @($seen.Values | Sort-Object -Property Id)
}

function Get-DartVmProcesses {
    # Πάντα επιστρέφει [object[]]· με Set-StrictMode το scalar Process δεν έχει .Count.
    $p = Get-Process -Name 'dartvm' -ErrorAction SilentlyContinue
    if ($null -eq $p) {
        return @()
    }
    return @($p | Sort-Object -Property Id)
}

function Stop-AllDartVmProcessesAuto {
    param([switch]$WhatIf)

    $list = @(Get-DartVmProcesses)
    if ($list.Count -eq 0) {
        Write-Step "Δεν τρέχει καμία διεργασία dartvm.exe."
        return $true
    }

    Write-Step "Βρέθηκαν $($list.Count) διεργασία/ες dartvm.exe — αυτόματος τερματισμός (Force)."
    foreach ($p in $list) {
        Write-Step "Τερματισμός dartvm.exe (PID=$($p.Id))."
        if ($WhatIf) {
            Write-Ok "[DryRun] Θα εκτελούνταν Stop-Process -Id $($p.Id) -Force"
            continue
        }
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Ok "Τερματίστηκε το dartvm.exe (PID=$($p.Id))."
        }
        catch {
            Write-Err "Δεν ήταν δυνατός ο τερματισμός του dartvm.exe (PID=$($p.Id)): $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

function Wait-DartVmGone {
    param(
        [int]$TimeoutSec = 45,
        [int]$PollMs = 300,
        [switch]$WhatIf
    )

    if ($WhatIf) {
        Write-Ok "[DryRun] Θα γινόταν αναμονή έως $TimeoutSec δευτ. μέχρι να μην υπάρχει dartvm.exe."
        return $true
    }

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    $n = 0
    while ($true) {
        $remaining = @(Get-DartVmProcesses)
        if ($remaining.Count -eq 0) {
            Write-Ok "Επιβεβαιώθηκε: δεν υπάρχει πλέον διεργασία dartvm.exe."
            return $true
        }
        if ([datetime]::UtcNow -ge $deadline) {
            Write-Err "Μετά από $TimeoutSec δευτ. εξακολουθούν να τρέχουν $($remaining.Count) dartvm.exe."
            return $false
        }
        $n++
        if (($n % 10) -eq 1) {
            Write-Step "Έλεγχος εκ νέου... ακόμα $($remaining.Count) dartvm.exe (PID: $($remaining.Id -join ', '))."
        }
        Start-Sleep -Milliseconds $PollMs
    }
}

function Resolve-HandleExe {
    $candidates = @(
        (Join-Path $PSScriptRoot 'handle64.exe'),
        (Join-Path $PSScriptRoot 'handle.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            return $c
        }
    }
    $cmd = Get-Command 'handle64.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd2 = Get-Command 'handle.exe' -ErrorAction SilentlyContinue
    if ($cmd2) { return $cmd2.Source }
    return $null
}

function Show-OptionalHandleHint {
    param([string]$PathForSearch)

    $hx = Resolve-HandleExe
    if (-not $hx) {
        Write-Step "Συμβουλή: Για λεπτομερή λίστα handles (ποιος κρατάει αρχείο/φάκελο), μπορείτε να χρησιμοποιήσετε το Sysinternals Handle (handle64.exe) και να το βάλετε στο PATH ή στον φάκελο scripts/."
        return
    }

    Write-Step "Βρέθηκε Handle στο: $hx (προαιρετική εκτέλεση για πληροφορίες — χωρίς αυτόματο κλείσιμο)."
    try {
        $quoted = '"{0}"' -f $PathForSearch
        & $hx -accepteula -nobanner $quoted 2>&1 | ForEach-Object { Write-Host ("    " + $_) }
    }
    catch {
        Write-Err "Αποτυχία εκτέλεσης Handle: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Step "Ρίζα project: $projectRoot"
Write-Step "Στόχος DLL: $dllPath"
Write-Step "Στόχος φακέλου hooks: $hooksDir"
if ($DryRun) {
    Write-Step "Λειτουργία DryRun: δεν θα γίνει τερματισμός ούτε διαγραφή."
}

if (Test-IsAdministrator) {
    Write-Ok "Τρέχετε ως διαχειριστής (elevated). Αυτό βοηθά σε τερματισμό/προβολή ορισμένων διεργασιών."
}
else {
    Write-Step "Δεν τρέχετε ως διαχειριστής. Συνήθως αρκεί για αρχεία στο user project· αν εμφανιστεί «Δεν επιτρέπεται η πρόσβαση», ανοίξτε νέο παράθυρο pwsh ως διαχειριστής και ξανατρέξτε την ίδια εντολή."
}

$dllExists = Test-Path -LiteralPath $dllPath
$hooksExists = Test-Path -LiteralPath $hooksDir -PathType Container
$terminateProcesses = $dllExists -and $hooksExists

if ($dllExists) {
    Write-Ok "Υπάρχει το αρχείο sqlite3.dll."
}
else {
    Write-Step "Δεν υπάρχει το sqlite3.dll στη διαδρομή build."
}

if ($hooksExists) {
    Write-Ok "Υπάρχει ο φάκελος .dart_tool\hooks_runner\sqlite3."
}
else {
    Write-Step "Δεν υπάρχει ο φάκελος .dart_tool\hooks_runner\sqlite3."
}

if (-not $terminateProcesses) {
    Write-Step "Παράλειψη τερματισμού διεργασιών: απαιτούνται και τα δύο (sqlite3.dll + φάκελος sqlite3). Χωρίς αυτά δεν έχει νόημα να κλείσουμε dartvm για αυτό το σενάριο."
}
else {
    $dllFull = Get-FullPathNormalized -LiteralPath $dllPath
    if ($dllFull) {
        Write-Ok "Κανονικοποιημένη διαδρομή DLL: $dllFull"
        $loaders = @(Get-ProcessesLoadingDll -DllFullPath $dllFull)
        $nonDart = @($loaders | Where-Object { $_.ProcessName -ne 'dartvm' })
        if ($nonDart.Count -gt 0) {
            Write-Step "Διεργασίες (εκτός dartvm) που φαίνεται να φορτώνουν το sqlite3.dll — δεν θα κλείσουν αυτόματα:"
            foreach ($x in $nonDart) {
                Write-Host ("    PID={0,-6} Όνομα={1}" -f $x.Id, $x.ProcessName)
            }
        }
    }

    # --- Αυτόματο κυνήγι dartvm (μόνο όταν υπάρχουν και DLL και φάκελος hooks) ---
    while ($true) {
        $okStop = Stop-AllDartVmProcessesAuto -WhatIf:$DryRun
        if (-not $okStop) {
            $c = Read-NumericChoice -Prompt "Ο τερματισμός dartvm απέτυχε. Επιλέξτε: 1=Επανάληψη τερματισμού 2=Χειροκίνητο κλείσιμο και συνέχεια 3=Τέλος script" -Min 1 -Max 3
            if ($c -eq 1) { continue }
            if ($c -eq 3) { exit 2 }
            while ($true) {
                $c2 = Read-NumericChoice -Prompt "Κλείστε χειροκίνητα τις dartvm.exe. Έπειτα: 1=Έτοιμος, συνεχίζω 2=Τέλος script" -Min 1 -Max 2
                if ($c2 -eq 2) { exit 2 }
                break
            }
            continue
        }

        $okWait = Wait-DartVmGone -WhatIf:$DryRun
        if ($okWait) { break }

        $c = Read-NumericChoice -Prompt "Το dartvm.exe παραμένει ενεργό. Επιλέξτε: 1=Επανάληψη αυτόματου τερματισμού 2=Χειροκίνητο κλείσιμο και συνέχεια 3=Τέλος script" -Min 1 -Max 3
        if ($c -eq 1) { continue }
        if ($c -eq 3) { exit 3 }
        while ($true) {
            $c2 = Read-NumericChoice -Prompt "Κλείστε χειροκίνητα τις dartvm.exe. Έπειτα: 1=Έτοιμος, συνεχίζω 2=Τέλος script" -Min 1 -Max 2
            if ($c2 -eq 2) { exit 3 }
            if ((Get-DartVmProcesses).Count -eq 0) { break }
            Write-Err "Ακόμα υπάρχει dartvm.exe."
        }
    }

    if (-not $DryRun) {
        Start-Sleep -Milliseconds 400
    }

    # --- Άλλες διεργασίες που φορτώνουν το DLL (ποτέ αυτόματα) ---
    $dllFull2 = Get-FullPathNormalized -LiteralPath $dllPath
    if ($dllFull2) {
        $others = @(Get-ProcessesLoadingDll -DllFullPath $dllFull2 | Where-Object { $_.ProcessName -ne 'dartvm' } | Sort-Object Id -Unique)
        foreach ($op in $others) {
            Write-Step "Διεργασία που φορτώνει sqlite3.dll: PID=$($op.Id) Όνομα=$($op.ProcessName)"
            $choice = Read-NumericChoice -Prompt "Επιλέξτε: 1=Τερματισμός αυτής της διεργασίας 2=Παράβλεψη (διατήρηση)" -Min 1 -Max 2
            if ($choice -eq 2) {
                Write-Step "Παραλείπεται ο τερματισμός για PID=$($op.Id)."
                continue
            }
            if ($DryRun) {
                Write-Ok "[DryRun] Θα εκτελούνταν Stop-Process -Id $($op.Id) -Force"
                continue
            }
            try {
                Stop-Process -Id $op.Id -Force -ErrorAction Stop
                Write-Ok "Τερματίστηκε η διεργασία PID=$($op.Id) ($($op.ProcessName))."
            }
            catch {
                Write-Err "Δεν ήταν δυνατός ο τερματισμός PID=$($op.Id): $($_.Exception.Message)"
                $c = Read-NumericChoice -Prompt "Επιλέξτε: 1=Δοκιμή ξανά τερματισμού 2=Συνέχεια χωρίς τερματισμό 3=Τέλος script" -Min 1 -Max 3
                if ($c -eq 3) { exit 4 }
                if ($c -eq 1) {
                    try {
                        Stop-Process -Id $op.Id -Force -ErrorAction Stop
                        Write-Ok "Τερματίστηκε η διεργασία PID=$($op.Id) στη δεύτερη προσπάθεια."
                    }
                    catch {
                        Write-Err "Και η δεύτερη προσπάθεια απέτυχε: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}

# --- Διαγραφές ---
if ($DryRun) {
    if ($terminateProcesses) {
        Write-Step "[DryRun] Ο τερματισμός διεργασιών παραπάνω αντικατοπτρίζει το πραγματικό σενάριο (υπήρχαν και DLL και φάκελος)."
    }
    else {
        Write-Step "[DryRun] Δεν θα είχε γίνει τερματισμός διεργασιών (λείπει ένας από τους δύο στόχους)."
    }
    if (Test-Path -LiteralPath $dllPath) {
        Write-Ok "[DryRun] Θα επιχειρούνταν διαγραφή αρχείου: $dllPath"
    }
    else {
        Write-Step "[DryRun] Δεν υπάρχει το αρχείο προς διαγραφή: $dllPath"
    }
    if (Test-Path -LiteralPath $hooksDir) {
        Write-Ok "[DryRun] Θα επιχειρούνταν διαγραφή φακέλου: $hooksDir"
    }
    else {
        Write-Step "[DryRun] Δεν υπάρχει ο φάκελος προς διαγραφή: $hooksDir"
    }
    Write-Ok "Ολοκλήρωση DryRun."
    exit 0
}

if (Test-Path -LiteralPath $dllPath) {
    Write-Step "Βρέθηκε το sqlite3.dll — διαγραφή..."
    if (Remove-PathWithRetry -Path $dllPath -MaxAttempts 12) {
        Write-Ok "Επιτυχής διαγραφή του sqlite3.dll."
    }
    else {
        Write-Step "Προβολή βοήθειας Handle (αν διαθέσιμο) για το DLL:"
        Show-OptionalHandleHint -PathForSearch $dllPath
        exit 5
    }
}
else {
    Write-Step "Δεν υπάρχει το sqlite3.dll (τίποτα να διαγραφεί)."
}

if (Test-Path -LiteralPath $hooksDir) {
    Write-Step "Βρέθηκε ο φάκελος hooks sqlite3 — διαγραφή..."
    if (Remove-PathWithRetry -Path $hooksDir -MaxAttempts 12) {
        Write-Ok "Επιτυχής διαγραφή του φακέλου .dart_tool\hooks_runner\sqlite3."
    }
    else {
        Write-Step "Προβολή βοήθειας Handle (αν διαθέσιμο) για τον φάκελο:"
        Show-OptionalHandleHint -PathForSearch $hooksDir
        exit 6
    }
}
else {
    Write-Step "Δεν υπάρχει ο φάκελος hooks sqlite3 (τίποτα να διαγραφεί)."
}

Write-Ok "Η διαδικασία ολοκληρώθηκε."
exit 0
