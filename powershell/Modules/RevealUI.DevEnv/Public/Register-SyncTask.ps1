#Requires -Version 7.0
#Requires -PSEdition Core

function Register-SyncTask {
    <#
    .SYNOPSIS
        Registers a Task Scheduler task to sync all repos every 30 minutes.
    .DESCRIPTION
        Creates a scheduled task that runs Sync-AllRepos -Target all every 30 minutes
        via pwsh.exe with inline module discovery. Requires elevation.
        Replaces the old RevealUI-only 15-minute task.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    if (-not (Test-IsAdmin)) {
        Write-DevLog 'Elevating to register sync task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Register-SyncTask' -Wait
        return
    }

    $taskName = 'RevealUI-Repo-Sync'
    $taskPath = '\RevealUI\'
    $oldTaskName = 'RevealUI-WSL-Sync'
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Unregister old task if present
    $oldTask = Get-ScheduledTask -TaskName $oldTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($oldTask) {
        Unregister-ScheduledTask -TaskName $oldTaskName -TaskPath $taskPath -Confirm:$false
        Write-DevLog "Unregistered old task '$taskPath$oldTaskName'" -Source 'TaskReg'
    }

    # Inline module discovery + Sync-AllRepos
    # Direct path check first (fast, no CIM dependency), then dynamic volume scan as fallback
    $command = @'
$knownPaths = @('C:\Users\joshu\.revealui', 'E:\.revealui', 'E:\professional\.revealui')
$r = $knownPaths | Where-Object { Test-Path "$_\powershell\Modules\RevealUI.DevEnv" } | Select-Object -First 1
if (-not $r) {
  $r = Get-Volume | Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):\.revealui"; "$($_.DriveLetter):\professional\.revealui" } |
    Where-Object { Test-Path "$_\powershell\Modules\RevealUI.DevEnv" } | Select-Object -First 1
}
if ($r) {
  $env:PSModulePath = (Join-Path $r 'powershell\Modules') + ';' + $env:PSModulePath
  Import-Module RevealUI.DevEnv
  Sync-AllRepos -Target all -TriggerSource scheduled
} else { Write-Error 'RevealUI.DevEnv module not found on any drive'; exit 1 }
'@

    # Base64 encode to avoid XML escaping issues
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Syncs all registered repos (C: and E:) with GitHub every 30 minutes.</Description>
    <Author>$currentUser</Author>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT30M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$currentUser</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <WakeToRun>false</WakeToRun>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>--headless pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", 'Register scheduled task')) {
        return
    }

    # Remove existing task if present
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue

    try {
        Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Xml $taskXml | Out-Null
        Write-DevLog "Scheduled task '$taskPath$taskName' registered successfully" -Source 'TaskReg'
    } catch {
        $err = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception, 'TaskRegistrationFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation, $taskName)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # Verify
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-DevLog 'Task registration failed — task not found after creation' -Level ERROR -Source 'TaskReg'
        return
    }

    Write-Host ''
    Write-DevLog "Verification:" -Source 'TaskReg'
    Write-Host "  Schedule: Every 30 minutes (indefinite)"
    Write-Host "  Engine:   conhost --headless pwsh.exe (PS7, no window)"
    Write-Host "  Command:  Sync-AllRepos -Target all -TriggerSource scheduled"
    Write-Host ''
}
