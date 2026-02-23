#Requires -Version 7.0
#Requires -PSEdition Core

function Register-SyncTask {
    <#
    .SYNOPSIS
        Registers a Task Scheduler task to sync RevealUI from WSL to Windows.
    .DESCRIPTION
        Creates a scheduled task that runs Sync-RevealUIToWindows every 15 minutes
        via pwsh.exe with inline module discovery. Requires elevation.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    if (-not (Test-IsAdmin)) {
        Write-DevLog 'Elevating to register sync task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Register-SyncTask' -Wait
        return
    }

    $taskName = 'RevealUI-WSL-Sync'
    $taskPath = '\RevealUI\'
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Inline module discovery + Sync command
    $command = @'
$r = Get-Volume | Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):\.revealui"; "$($_.DriveLetter):\professional\.revealui" } |
  Where-Object { Test-Path "$_\powershell\Modules\RevealUI.DevEnv" } | Select-Object -First 1
if ($r) {
  $env:PSModulePath = (Join-Path $r 'powershell\Modules') + ';' + $env:PSModulePath
  Import-Module RevealUI.DevEnv
  Sync-RevealUIToWindows -TriggerSource scheduled
} else { Write-Error 'RevealUI.DevEnv module not found on any drive' }
'@

    # Base64 encode to avoid XML escaping issues
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Syncs RevealUI from WSL to Windows every 15 minutes for read-only access by Windows apps.</Description>
    <Author>$currentUser</Author>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT15M</Interval>
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
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <WakeToRun>false</WakeToRun>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>pwsh.exe</Command>
      <Arguments>-NonInteractive -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded</Arguments>
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
    Write-Host "  Schedule: Every 15 minutes (indefinite)"
    Write-Host "  Engine:   pwsh.exe (PowerShell 7)"
    Write-Host "  Command:  Sync-RevealUIToWindows -TriggerSource scheduled"
    Write-Host ''
}
