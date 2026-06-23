#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    Import-Module (Join-Path $script:ModuleRoot 'RevealUI.RevStation.psd1') -Force 6> $null
}

AfterAll {
    Remove-Module RevealUI.RevStation -Force -ErrorAction SilentlyContinue
}

# Regression guard for the ShouldProcess contract: the self-elevation branch must be
# gated by ShouldProcess so that -WhatIf previews instead of triggering a real UAC
# prompt + scheduled-task removal. See Mount-WSLDev for the reference pattern.
Describe 'Unregister-DevMountTask self-elevation -WhatIf contract' {
    BeforeEach {
        # Force the non-elevated path and stub the side-effecting helpers so no UAC
        # prompt or scheduled-task removal can occur during the test.
        Mock Test-IsAdmin    { $false } -ModuleName RevealUI.RevStation
        Mock Invoke-Elevated { }        -ModuleName RevealUI.RevStation
        Mock Write-DevLog    { }        -ModuleName RevealUI.RevStation
    }

    It 'does not elevate under -WhatIf (no Invoke-Elevated call)' {
        Unregister-DevMountTask -WhatIf
        Should -Invoke Invoke-Elevated -Times 0 -Exactly -ModuleName RevealUI.RevStation
    }

    It 'elevates on a normal confirmed run' {
        # ConfirmImpact = High, so -Confirm:$false keeps the run non-interactive.
        Unregister-DevMountTask -Confirm:$false
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ModuleName RevealUI.RevStation
    }
}
