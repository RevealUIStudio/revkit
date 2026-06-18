# Register-VHDxCompactTask.ps1 — Create scheduled task for weekly VHDx compaction
# Run once, elevated. Task runs every Sunday at 4 AM.

$taskName = "WSL-VHDx-Compact"
$scriptPath = "$env:USERPROFILE\.revealui\wsl\compact-vhdx.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Script not found: $scriptPath"
    exit 1
}

# Remove existing task if present
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed existing task: $taskName"
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'Weekly WSL VHDx compaction - reclaims freed space on C:' `
    -RunLevel Highest

Write-Host "Registered scheduled task: $taskName (Sundays at 4 AM)"
Write-Host "  Script: $scriptPath"
Write-Host "  Run manually: schtasks /run /tn $taskName"
