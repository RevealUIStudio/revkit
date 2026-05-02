#Requires -Version 7.0
#Requires -PSEdition Core

function Sync-RevealUIToWindows {
    <#
    .SYNOPSIS
        Syncs RevealUI on Windows (C: drive) with GitHub via git pull --ff-only.
    .DESCRIPTION
        Fetches from origin and fast-forward merges. Skips if the working tree is
        dirty or if fast-forward is not possible. Replaces the old robocopy-based
        mirror approach — C: is now a full git clone, not a read-only copy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [ValidateSet('manual', 'scheduled')]
        [string]$TriggerSource = 'manual',

        [string]$RepoPath = (Join-Path $env:USERPROFILE 'projects\RevealUI')
    )

    $logDir = Get-ModuleLogPath
    $logFile = Join-Path $logDir 'sync-revealui.log'

    Write-DevLog "Starting RevealUI sync ($TriggerSource)" -Source 'Sync' -LogFile $logFile

    if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
        Write-DevLog "Not a git repo: $RepoPath" -Level ERROR -Source 'Sync' -LogFile $logFile
        return
    }

    # Check for uncommitted changes
    $dirty = git -C $RepoPath status --porcelain 2>&1
    if ($dirty) {
        Write-DevLog "Skipping RevealUI: uncommitted changes" -Level WARN -Source 'Sync' -LogFile $logFile
        Write-Warning "Skipping RevealUI sync — uncommitted changes in $RepoPath"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($RepoPath, 'git pull --ff-only')) {
        return
    }

    git -C $RepoPath fetch origin main --quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-DevLog "Fetch failed for RevealUI" -Level ERROR -Source 'Sync' -LogFile $logFile
        return
    }

    $pullOutput = git -C $RepoPath pull --ff-only origin main 2>&1
    if ($LASTEXITCODE -eq 0) {
        $sha = git -C $RepoPath rev-parse --short HEAD
        Write-DevLog "RevealUI synced to $sha" -Source 'Sync' -LogFile $logFile
    } else {
        Write-DevLog "Pull --ff-only failed: $pullOutput" -Level WARN -Source 'Sync' -LogFile $logFile
        Write-Warning "RevealUI sync failed (not fast-forwardable)"
    }
}
