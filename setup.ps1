$ErrorActionPreference = 'Stop'

$ProjectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$TimetablePath = Join-Path $ProjectDirectory 'timetable.json'
$ReminderScript = Join-Path $ProjectDirectory 'reminder.py'
$TaskPrefix = 'PersonalReminder-'
$PythonCandidates = @(
    (Join-Path $ProjectDirectory '.venv\Scripts\python.exe'),
    (Join-Path $ProjectDirectory 'venv\Scripts\python.exe')
)
$PythonPath = $PythonCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if (-not $PythonPath) {
    throw "Python virtual environment not found. Create .venv in $ProjectDirectory and install requirements.txt."
}
if (-not (Test-Path -LiteralPath $TimetablePath -PathType Leaf)) {
    throw "Timetable file not found: $TimetablePath"
}
if (-not (Test-Path -LiteralPath $ReminderScript -PathType Leaf)) {
    throw "Reminder script not found: $ReminderScript"
}

Push-Location $ProjectDirectory
try {
    $TimetableJson = & $PythonPath -c "import json; from pathlib import Path; from reminder import load_timetable; data=json.loads(Path('timetable.json').read_text(encoding='utf-8')); print(json.dumps({'timezone': data.get('timezone'), 'schedule': load_timetable()}))"
    if ($LASTEXITCODE -ne 0) {
        throw "Timetable validation failed. See the Python error above."
    }
}
finally {
    Pop-Location
}

try {
    $Timetable = $TimetableJson -join "`n" | ConvertFrom-Json -ErrorAction Stop
    $Schedule = @($Timetable.schedule)
}
catch {
    throw "Could not read validated timetable output: $($_.Exception.Message)"
}

# Task Scheduler interprets daily trigger times in the computer's local time zone.
# The initial timetable is Asia/Kolkata, which maps to this Windows time-zone ID.
$ExpectedWindowsTimeZone = 'India Standard Time'
$CurrentTimeZone = (Get-TimeZone).Id
if ($Timetable.timezone -ne 'Asia/Kolkata') {
    throw "This setup supports the timetable timezone 'Asia/Kolkata'; timetable.json currently specifies '$($Timetable.timezone)'."
}
if ($CurrentTimeZone -ne $ExpectedWindowsTimeZone) {
    throw "Timetable timezone Asia/Kolkata requires Windows time zone '$ExpectedWindowsTimeZone'; this computer uses '$CurrentTimeZone'. Change the timetable timezone or Windows time zone before setup."
}

$EnabledReminders = @($Schedule | Where-Object { $_.enabled -eq $true })
$DesiredTasks = @{}
foreach ($Reminder in $EnabledReminders) {
    $TaskSuffix = [regex]::Replace([string]$Reminder.title, '[^\p{L}\p{Nd}]', '')
    if ([string]::IsNullOrWhiteSpace($TaskSuffix)) {
        throw "Reminder title '$($Reminder.title)' does not contain any letters or digits for a task name."
    }
    $TaskName = $TaskPrefix + $TaskSuffix
    if ($DesiredTasks.ContainsKey($TaskName)) {
        throw "Reminder titles produce the same task name '$TaskName'. Rename one of the titles."
    }
    $DesiredTasks[$TaskName] = $Reminder
}

function ConvertTo-CommandLineArgument([string]$Value) {
    $Builder = [System.Text.StringBuilder]::new()
    [void]$Builder.Append('"')
    $Backslashes = 0
    foreach ($Character in $Value.ToCharArray()) {
        if ($Character -eq '\') {
            $Backslashes++
            continue
        }
        if ($Character -eq '"') {
            [void]$Builder.Append(('\' * (2 * $Backslashes + 1)))
            [void]$Builder.Append('"')
        }
        else {
            if ($Backslashes -gt 0) {
                [void]$Builder.Append(('\' * $Backslashes))
            }
            [void]$Builder.Append($Character)
        }
        $Backslashes = 0
    }
    if ($Backslashes -gt 0) {
        [void]$Builder.Append(('\' * (2 * $Backslashes)))
    }
    [void]$Builder.Append('"')
    return $Builder.ToString()
}

$ExistingManagedTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName.StartsWith($TaskPrefix, [System.StringComparison]::OrdinalIgnoreCase) })
$ExistingNames = @{}
foreach ($Task in $ExistingManagedTasks) {
    $ExistingNames[$Task.TaskName] = $true
}

$CreatedCount = 0
$UpdatedCount = 0
foreach ($TaskName in $DesiredTasks.Keys) {
    $Reminder = $DesiredTasks[$TaskName]
    $TimeOfDay = [TimeSpan]::ParseExact([string]$Reminder.time, 'hh\:mm', [Globalization.CultureInfo]::InvariantCulture)
    $TriggerTime = [datetime]::Today.Add($TimeOfDay)
    $ReminderArgument = ConvertTo-CommandLineArgument ([string]$Reminder.title)
    $ScriptArgument = ConvertTo-CommandLineArgument $ReminderScript
    $Action = New-ScheduledTaskAction -Execute $PythonPath -Argument "$ScriptArgument --reminder $ReminderArgument --scheduled" -WorkingDirectory $ProjectDirectory -ErrorAction Stop
    $Trigger = New-ScheduledTaskTrigger -Daily -At $TriggerTime -ErrorAction Stop
    $Principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited -ErrorAction Stop
    $Settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ErrorAction Stop

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Description "Personal Reminder notification for '$($Reminder.title)'" -Force -ErrorAction Stop | Out-Null
    if ($ExistingNames.ContainsKey($TaskName)) {
        $UpdatedCount++
    }
    else {
        $CreatedCount++
    }
}

$RemovedCount = 0
foreach ($Task in $ExistingManagedTasks) {
    if (-not $DesiredTasks.ContainsKey($Task.TaskName)) {
        Unregister-ScheduledTask -TaskName $Task.TaskName -Confirm:$false -ErrorAction Stop
        $RemovedCount++
    }
}

Write-Host "Personal Reminder setup complete."
Write-Host "Project: $ProjectDirectory"
Write-Host "Python:  $PythonPath"
Write-Host "Tasks created: $CreatedCount; updated: $UpdatedCount; removed: $RemovedCount."
Write-Host "Enabled reminders scheduled: $($EnabledReminders.Count)."
