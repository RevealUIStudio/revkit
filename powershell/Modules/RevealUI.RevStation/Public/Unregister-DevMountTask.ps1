#Requires -Version 7.0
#Requires -PSEdition Core

function Unregister-DevMountTask {
    <#
    .SYNOPSIS
        Removes the WSL Sandbox drive auto-mount scheduled task.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param()

    $taskName = 'WSL-Mount-DevDrive'

    if (-not (Test-IsAdmin)) {
        if (-not $PSCmdlet.ShouldProcess($taskName, 'Elevate to unregister scheduled task')) {
            return
        }
        Write-DevLog 'Elevating to unregister mount task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Unregister-DevMountTask' -Wait
        return
    }

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
