#Requires -Version 7.0
#Requires -PSEdition Core

function Unregister-DevMountTask {
    <#
    .SYNOPSIS
        Removes the WSL Forge drive auto-mount scheduled task.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param()

    if (-not (Test-IsAdmin)) {
        Write-DevLog 'Elevating to unregister mount task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Unregister-DevMountTask' -Wait
        return
    }

    $taskName = 'WSL-Mount-DevDrive'

    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-DevLog "Task '$taskName' not found — nothing to remove" -Level WARN -Source 'TaskReg'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($taskName, 'Unregister scheduled task')) {
        return
    }

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-DevLog "Task '$taskName' removed" -Source 'TaskReg'
}
