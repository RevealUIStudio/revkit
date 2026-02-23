#Requires -Version 7.0
#Requires -PSEdition Core

function Unregister-SyncTask {
    <#
    .SYNOPSIS
        Removes the RevealUI WSL-to-Windows sync scheduled task.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param()

    if (-not (Test-IsAdmin)) {
        Write-DevLog 'Elevating to unregister sync task...' -Level WARN -Source 'TaskReg'
        Invoke-Elevated -Command 'Unregister-SyncTask' -Wait
        return
    }

    $taskName = 'RevealUI-WSL-Sync'
    $taskPath = '\RevealUI\'

    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-DevLog "Task '$taskPath$taskName' not found — nothing to remove" -Level WARN -Source 'TaskReg'
        return
    }

    if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", 'Unregister scheduled task')) {
        return
    }

    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
    Write-DevLog "Task '$taskPath$taskName' removed" -Source 'TaskReg'
}
