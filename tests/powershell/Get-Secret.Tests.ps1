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

Describe 'Get-Secret path validation (injection guard)' {
    It 'throws InvalidPath when the path is whitespace only' {
        { Get-Secret -Path '   ' -AsPlainText -ErrorAction Stop } | Should -Throw -ErrorId 'InvalidPath,Get-Secret'
    }

    It 'throws InvalidPath when the path contains a newline' {
        { Get-Secret -Path "a`nb" -AsPlainText -ErrorAction Stop } | Should -Throw -ErrorId 'InvalidPath,Get-Secret'
    }

    It 'throws InvalidPath when the path contains a carriage return' {
        { Get-Secret -Path "a`rb" -AsPlainText -ErrorAction Stop } | Should -Throw -ErrorId 'InvalidPath,Get-Secret'
    }

    It 'rejects control characters before any WSL drive lookup is attempted' {
        # REVEALUI_ROOT points nowhere usable; a DriveNotFound error would prove
        # the control-character guard did NOT run first. InvalidPath proves it did.
        $env:REVEALUI_ROOT = 'Z:\does-not-exist'
        { Get-Secret -Path "x`ny" -AsPlainText -ErrorAction Stop } | Should -Throw -ErrorId 'InvalidPath,Get-Secret'
    }
}
