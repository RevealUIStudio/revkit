#Requires -Version 7.0
#Requires -PSEdition Core

<#
.SYNOPSIS
    Installs pre-commit and pre-push guard hooks on all E: drive backup repos.
.DESCRIPTION
    Copies backup-guard-pre-commit.sh and backup-guard-pre-push.sh into .git/hooks/
    for every repo under E:\repos\. Idempotent — safe to re-run.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$scriptDir = $PSScriptRoot
$backupBase = 'E:\repos'

if (-not (Test-Path $backupBase)) {
    Write-Warning "Backup drive not available at $backupBase"
    return
}

$preCommitSrc = Join-Path $scriptDir 'backup-guard-pre-commit.sh'
$prePushSrc = Join-Path $scriptDir 'backup-guard-pre-push.sh'

if (-not (Test-Path $preCommitSrc) -or -not (Test-Path $prePushSrc)) {
    Write-Error "Guard hook scripts not found in $scriptDir"
    return
}

# -Filter '.git' misses dotfiles on some Windows filesystems; use -Force and name match
$repos = Get-ChildItem -Path $backupBase -Recurse -Directory -Force -Depth 2 |
    Where-Object { $_.Name -eq '.git' }

foreach ($gitDir in $repos) {
    $repoPath = $gitDir.Parent.FullName
    $hooksDir = Join-Path $gitDir.FullName 'hooks'
    $repoName = $repoPath -replace [regex]::Escape($backupBase), '' -replace '^\\', ''

    if (-not (Test-Path $hooksDir)) {
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    }

    $preCommitDst = Join-Path $hooksDir 'pre-commit'
    $prePushDst = Join-Path $hooksDir 'pre-push'

    if ($PSCmdlet.ShouldProcess($repoName, 'Install backup guard hooks')) {
        Copy-Item -Path $preCommitSrc -Destination $preCommitDst -Force
        Copy-Item -Path $prePushSrc -Destination $prePushDst -Force
        Write-Host "  Installed guards: $repoName" -ForegroundColor Green
    }
}

Write-Host "`nBackup guards installed on all E:\repos\ clones." -ForegroundColor Cyan
