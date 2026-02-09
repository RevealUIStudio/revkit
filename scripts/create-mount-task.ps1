# Create Task Scheduler task for auto-mounting WSL dev drive
# Run this in an ELEVATED PowerShell session (Run as Administrator)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell > Run as Administrator, then run this script again." -ForegroundColor Yellow
    exit 1
}

$taskName = "WSL-Mount-DevDrive"

# Resolve mount script path: prefer SSD location, fallback to C:\Scripts
$scriptPath = Join-Path $PSScriptRoot "mount-wsl-dev.ps1"
if (-not (Test-Path $scriptPath)) {
    $scriptPath = "C:\Scripts\mount-wsl-dev.ps1"
}

Write-Host "Creating scheduled task: $taskName" -ForegroundColor Cyan
Write-Host "  Script: $scriptPath" -ForegroundColor Gray

# Remove existing task if present
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Define the action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Trigger: At user logon
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Principal: run as the user with highest privileges (admin)
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType S4U `
    -RunLevel Highest

# Register the task with logon trigger
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $triggerLogon `
    -Settings $settings `
    -Principal $principal `
    -Description "Auto-mount WD My Passport SSD to WSL at /mnt/wsl-dev" `
    -Force | Out-Null

# Now add the USB device arrival event trigger
try {
    $task = Get-ScheduledTask -TaskName $taskName

    # Create event trigger for USB device insertion
    $CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $triggerUSB = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $triggerUSB.Subscription = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-Kernel-PnP/Device Configuration">
    <Select Path="Microsoft-Windows-Kernel-PnP/Device Configuration">*[System[(EventID=400)]]</Select>
  </Query>
</QueryList>
"@
    $triggerUSB.Enabled = $true
    $triggerUSB.Delay = "PT10S"

    # Add USB trigger alongside the existing logon trigger
    $allTriggers = @($task.Triggers)
    $allTriggers += $triggerUSB
    $task.Triggers = $allTriggers
    $task | Set-ScheduledTask | Out-Null

    Write-Host "Scheduled task '$taskName' created successfully" -ForegroundColor Green
    Write-Host "Triggers:" -ForegroundColor Cyan
    Write-Host "  - At user logon ($env:USERNAME)" -ForegroundColor White
    Write-Host "  - On USB device insertion (10s delay)" -ForegroundColor White
} catch {
    Write-Host "Task created with logon trigger only." -ForegroundColor Yellow
    Write-Host "USB event trigger failed: $_" -ForegroundColor Yellow
    Write-Host "The drive will still auto-mount at login." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To test: Run 'Get-ScheduledTask -TaskName $taskName | Start-ScheduledTask'" -ForegroundColor Cyan
