$ErrorActionPreference = 'Stop'
$ProjectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonCandidates = @(
    (Join-Path $ProjectDirectory '.venv\Scripts\python.exe'),
    (Join-Path $ProjectDirectory 'venv\Scripts\python.exe')
)
$PythonPath = $PythonCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
$FailureCount = 0

function Write-TestResult([string]$Name, [bool]$Passed, [string]$Details = '') {
    if ($Passed) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $Name$(if ($Details) { ': ' + $Details })" -ForegroundColor Red
        $script:FailureCount++
    }
}

if ($PythonPath) {
    $VersionOutput = & $PythonPath --version 2>&1
    Write-TestResult 'Python is available' ($LASTEXITCODE -eq 0) ($VersionOutput -join ' ')
    Write-TestResult 'Virtual environment exists' $true $PythonPath
}
else {
    Write-TestResult 'Python is available' $false 'No working project virtual environment was found.'
    Write-TestResult 'Virtual environment exists' $false 'Expected .venv or venv under the project folder.'
}

function Invoke-PythonTest([string]$Name, [string[]]$Arguments) {
    if (-not $script:PythonPath) {
        Write-TestResult $Name $false 'Skipped because the virtual environment is unavailable.'
        return
    }

    Push-Location $script:ProjectDirectory
    try {
        $Output = & $script:PythonPath @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($ExitCode -eq 0) {
        Write-TestResult $Name $true
    }
    else {
        Write-TestResult $Name $false ($Output -join ' ')
    }
}

Invoke-PythonTest 'Dependencies are installed' @('-c', 'import winotify')
Invoke-PythonTest 'timetable.json is valid' @('-c', 'from reminder import load_timetable; reminders=load_timetable(); assert reminders, "schedule is empty"')
Invoke-PythonTest 'Test notification works' @('reminder.py', '--test')

if ($PythonPath) {
    Push-Location $ProjectDirectory
    try {
        $LookupTitle = & $PythonPath -c 'from reminder import load_timetable; print(next((r["title"] for r in load_timetable() if r["enabled"]), ""))' 2>&1
        $LookupExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $LookupTitle = ($LookupTitle -join "`n").Trim()
    if ($LookupExitCode -ne 0 -or -not $LookupTitle) {
        Write-TestResult 'Reminder lookup works' $false 'No enabled reminder is available for the lookup check.'
    }
    else {
        Invoke-PythonTest "Reminder lookup works ($LookupTitle)" @('reminder.py', '--reminder', $LookupTitle)
    }
}
else {
    Invoke-PythonTest 'Reminder lookup works' @('reminder.py', '--reminder', 'DSA')
}

if ($FailureCount -eq 0) {
    Write-Host 'All checks passed.' -ForegroundColor Green
    exit 0
}

Write-Host "$FailureCount check(s) failed." -ForegroundColor Red
exit 1
