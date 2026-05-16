#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    Import-Module (Join-Path $script:ModuleRoot 'RevealUI.RevStation.psd1') -Force 6> $null

    $script:DocsPath = Join-Path $script:ModuleRoot 'docs' 'WSL-QuickReference.md'
}

AfterAll {
    Remove-Module RevealUI.RevStation -Force -ErrorAction SilentlyContinue
}

Describe 'Show-WSLHelp' {
    It 'ships WSL-QuickReference.md at the module-relative docs path' {
        # The function's primary code path resolves docs via Split-Path $PSScriptRoot,
        # which only works if the file is actually present in the module's docs/ dir.
        Test-Path $script:DocsPath | Should -BeTrue
    }

    It 'is exported as a function from the module' {
        Get-Command Show-WSLHelp -Module RevealUI.RevStation | Should -Not -BeNullOrEmpty
    }

    # NOTE: invoking Show-WSLHelp itself launches notepad.exe (Windows-only) or
    # surfaces a host warning. Mocking native .exe invocations is unreliable in
    # Pester, so behavioral tests of the launch path live with the integration
    # suite (operator-run, manual smoke test during bootstrap verification).
}
