#Requires -Version 7.0
#Requires -PSEdition Core

function Sync-AllRepos {
    <#
    .SYNOPSIS
        Syncs all registered repos on C: and/or E: drives with GitHub.
    .DESCRIPTION
        C: repos use git pull --ff-only (skips if dirty or diverged).
        E: repos use git fetch + reset --hard origin/main (always matches GitHub).
        E: drive is optional — skipped gracefully if unavailable.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateSet('c', 'e', 'all')]
        [string]$Target = 'all',

        [ValidateSet('manual', 'scheduled')]
        [string]$TriggerSource = 'manual'
    )

    $logDir = Get-ModuleLogPath
    $logFile = Join-Path $logDir 'sync-all.log'

    $cBase = 'C:\Users\joshu'
    $eBase = 'E:\repos'

    # Repo registry — hardcoded for now, config.toml later
    $repos = @(
        @{ Name = 'RevealUI';          CPath = 'projects\RevealUI';          EPath = 'professional\RevealUI';          Identity = 'professional' }
        @{ Name = 'revault';            CPath = 'projects\revault';            EPath = 'professional\revault';            Identity = 'professional' }
        @{ Name = 'devkit';             CPath = '.revealui';                   EPath = 'professional\devkit';             Identity = 'professional' }
        @{ Name = 'portfolio';          CPath = 'projects\portfolio';          EPath = 'personal\portfolio';              Identity = 'personal' }
        @{ Name = 'joshua-v-dev';       CPath = 'projects\joshua-v-dev';       EPath = 'personal\joshua-v-dev';           Identity = 'personal' }
        @{ Name = 'off-set-designs';    CPath = 'projects\off-set-designs';    EPath = 'personal\off-set-designs';        Identity = 'personal' }
        @{ Name = 'angler-adventures';  CPath = 'projects\angler-adventures';  EPath = 'personal\angler-adventures';      Identity = 'personal' }
        @{ Name = 'supaturbo';          CPath = 'projects\supaturbo';          EPath = 'personal\supaturbo';              Identity = 'personal' }
        @{ Name = 'flow';               CPath = 'projects\flow';               EPath = 'personal\flow';                   Identity = 'personal' }
        @{ Name = 'igotmaps';           CPath = 'projects\igotmaps';           EPath = 'personal\igotmaps';               Identity = 'personal' }
    )

    $eAvailable = Test-Path $eBase
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    Write-DevLog "Starting sync ($TriggerSource, target=$Target)" -Source 'SyncAll' -LogFile $logFile

    foreach ($repo in $repos) {
        # --- C: drive sync ---
        if ($Target -in 'c', 'all') {
            $cFullPath = Join-Path $cBase $repo.CPath

            if (-not (Test-Path (Join-Path $cFullPath '.git'))) {
                $results.Add([PSCustomObject]@{ Drive = 'C:'; Repo = $repo.Name; Status = 'SKIP (not cloned)'; Branch = '-' })
            } else {
                $branch = git -C $cFullPath rev-parse --abbrev-ref HEAD 2>&1
                $dirty = git -C $cFullPath status --porcelain 2>&1
                if ($dirty) {
                    $results.Add([PSCustomObject]@{ Drive = 'C:'; Repo = $repo.Name; Status = "DIRTY ($(@($dirty).Count) changes)"; Branch = $branch })
                    Write-DevLog "C: $($repo.Name): skipped (dirty)" -Level WARN -Source 'SyncAll' -LogFile $logFile
                } else {
                    git -C $cFullPath fetch origin --quiet 2>&1 | Out-Null
                    $pullOutput = git -C $cFullPath pull --ff-only 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $results.Add([PSCustomObject]@{ Drive = 'C:'; Repo = $repo.Name; Status = 'OK'; Branch = $branch })
                    } else {
                        $results.Add([PSCustomObject]@{ Drive = 'C:'; Repo = $repo.Name; Status = 'DIVERGED'; Branch = $branch })
                        Write-DevLog "C: $($repo.Name): pull --ff-only failed" -Level WARN -Source 'SyncAll' -LogFile $logFile
                    }
                }
            }
        }

        # --- E: drive sync ---
        if ($Target -in 'e', 'all') {
            if (-not $eAvailable) {
                continue
            }

            $eFullPath = Join-Path $eBase $repo.EPath

            if (-not (Test-Path (Join-Path $eFullPath '.git'))) {
                $results.Add([PSCustomObject]@{ Drive = 'E:'; Repo = $repo.Name; Status = 'SKIP (not cloned)'; Branch = '-' })
            } else {
                $branch = git -C $eFullPath rev-parse --abbrev-ref HEAD 2>&1
                git -C $eFullPath fetch origin --quiet 2>&1 | Out-Null
                $resetOutput = git -C $eFullPath reset --hard "origin/$branch" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $results.Add([PSCustomObject]@{ Drive = 'E:'; Repo = $repo.Name; Status = 'OK'; Branch = $branch })
                } else {
                    $results.Add([PSCustomObject]@{ Drive = 'E:'; Repo = $repo.Name; Status = "RESET FAILED"; Branch = $branch })
                    Write-DevLog "E: $($repo.Name): reset failed: $resetOutput" -Level ERROR -Source 'SyncAll' -LogFile $logFile
                }
            }
        }
    }

    if ($Target -in 'e', 'all' -and -not $eAvailable) {
        Write-DevLog "E: drive not available — backup sync skipped" -Level WARN -Source 'SyncAll' -LogFile $logFile
        Write-Warning "E: drive not available — backup sync skipped"
    }

    $okCount = ($results | Where-Object Status -eq 'OK').Count
    $totalCount = $results.Count
    Write-DevLog "Sync complete: $okCount/$totalCount OK ($TriggerSource)" -Source 'SyncAll' -LogFile $logFile

    Write-Host "`n=== Sync Results ===" -ForegroundColor Green
    $results | Format-Table -AutoSize

    return $results
}

Set-Alias -Name syncall -Value Sync-AllRepos
