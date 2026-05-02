#Requires -Version 7.0
#Requires -PSEdition Core

function Register-WSLHealthTask {
    <#
    .SYNOPSIS
        Registers a Task Scheduler task to monitor WSL health every 3 minutes.
    .DESCRIPTION
        Creates a scheduled task that runs Invoke-WSLRecovery via pwsh.exe with inline
        module discovery. Detects zombie WSL states and auto-recovers. Requires elevation.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    if (-not (Test-IsAdmin)) {
        Write-DevLog 'Elevating to register health task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Register-WSLHealthTask' -Wait
        return
    }

    $taskName = 'WSL-Health-Monitor'

    # Inline module discovery + Invoke-WSLRecovery command
    $command = @'
$r = Get-Volume | Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):\.revealui"; "$($_.DriveLetter):\professional\.revealui" } |
  Where-Object { Test-Path "$_\powershell\Modules\RevealUI.RevStation" } | Select-Object -First 1
if ($r) {
  $env:PSModulePath = (Join-Path $r 'powershell\Modules') + ';' + $env:PSModulePath
  Import-Module RevealUI.RevStation
  Invoke-WSLRecovery -TriggerSource scheduled
} else { Write-Error 'RevealUI.RevStation module not found on any drive' }
'@

    # Base64 encode to avoid XML escaping issues
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Monitor WSL health every 3 minutes and auto-recover zombie VM states</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Enabled>true</Enabled>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Repetition>
        <Interval>PT3M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$($env:USERDOMAIN)\$($env:USERNAME)</UserId>
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
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>--headless pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    if (-not $PSCmdlet.ShouldProcess($taskName, 'Register scheduled task')) {
        return
    }

    # Remove existing task if present
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    try {
        Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
        Write-DevLog "Scheduled task '$taskName' registered successfully" -Source 'TaskReg'
    } catch {
        $err = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception, 'TaskRegistrationFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation, $taskName)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # Verify
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-DevLog 'Task registration failed — task not found after creation' -Level ERROR -Source 'TaskReg'
        return
    }

    Write-Host ''
    Write-DevLog "Verification:" -Source 'TaskReg'
    Write-Host "  Trigger:   every 3 minutes (PT3M)"
    Write-Host "  Engine:    conhost --headless pwsh.exe (PS7, no window)"
    Write-Host "  RunLevel:  $($task.Principal.RunLevel)"
    Write-Host "  TimeLimit: PT2M"
    Write-Host ''
}
