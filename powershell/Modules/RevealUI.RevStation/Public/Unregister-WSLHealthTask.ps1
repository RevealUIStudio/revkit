#Requires -Version 7.0
#Requires -PSEdition Core

function Unregister-WSLHealthTask {
    <#
    .SYNOPSIS
        Removes the WSL-Health-Monitor scheduled task.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param()

    if (-not (Test-IsAdmin)) {
        Write-DevLog 'Elevating to unregister health task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Unregister-WSLHealthTask' -Wait
        return
    }

    $taskName = 'WSL-Health-Monitor'

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "Task '$taskName' not found — nothing to remove."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($taskName, 'Unregister scheduled task')) {
        return
    }

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-DevLog "Scheduled task '$taskName' removed" -Source 'TaskReg'
}
