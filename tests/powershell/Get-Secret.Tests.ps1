#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    Import-Module (Join-Path $script:ModuleRoot 'RevealUI.RevStation.psd1') -Force 6> $null

    $script:OrigRoot = $env:REVEALUI_ROOT
}

AfterAll {
    Remove-Module RevealUI.RevStation -Force -ErrorAction SilentlyContinue
    if ($null -ne $script:OrigRoot) { $env:REVEALUI_ROOT = $script:OrigRoot } else { Remove-Item Env:REVEALUI_ROOT -ErrorAction SilentlyContinue }
}

Describe 'Get-Secret argument validation' {
    It 'throws OutputModeRequired when neither -AsPlainText nor -AsSecureString is given' {
        { Get-Secret -Path 'test/path' -ErrorAction Stop } | Should -Throw -ErrorId 'OutputModeRequired,Get-Secret'
    }

    It 'requires a -Path argument' {
        # Without -Path, the [Parameter(Mandatory)] decoration prevents invocation
        { Get-Secret -AsPlainText -ErrorAction Stop } | Should -Throw
    }
}
