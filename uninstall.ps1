$ErrorActionPreference = 'Stop'
$TaskPrefix = 'PersonalReminder-'
$ManagedTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName.StartsWith($TaskPrefix, [System.StringComparison]::OrdinalIgnoreCase) })

foreach ($Task in $ManagedTasks) {
    Unregister-ScheduledTask -TaskName $Task.TaskName -Confirm:$false -ErrorAction Stop
    Write-Host "Removed $($Task.TaskName)"
}

if ($ManagedTasks.Count -eq 0) {
    Write-Host 'No PersonalReminder- tasks were found.'
}
else {
    Write-Host "Removed $($ManagedTasks.Count) PersonalReminder- task(s)."
}
