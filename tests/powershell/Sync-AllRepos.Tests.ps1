#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    $script:SyncAllReposPath = Join-Path $script:ModuleRoot 'Public' 'Sync-AllRepos.ps1'
}

Describe 'Sync-AllRepos deprecation marker' {
    It 'has the DEPRECATED 2026-05-08 marker in its source comment block' {
        $content = Get-Content -Raw -Path $script:SyncAllReposPath
        $content | Should -Match 'DEPRECATED 2026-05-08'
    }

    It 'documents the retired sync registry rationale' {
        $content = Get-Content -Raw -Path $script:SyncAllReposPath
        $content | Should -Match 'RevealUI-Repo-Sync'
        $content | Should -Match 'RevealUI-WSL-Weekly-Backup'
    }

    It 'still parses as valid PowerShell' {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:SyncAllReposPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        $parseErrors | Should -BeNullOrEmpty
    }
}
