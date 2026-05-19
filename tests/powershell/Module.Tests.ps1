#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'RevealUI.RevStation.psd1'
}

Describe 'RevealUI.RevStation manifest' {
    It 'parses as a valid module manifest' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'declares ModuleVersion in the 0.6.x line' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.Version.Major | Should -Be 0
        $manifest.Version.Minor | Should -Be 6
    }

    It 'requires PowerShell 7+' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.PowerShellVersion | Should -BeGreaterOrEqual ([Version]'7.0')
    }

    It 'targets Core edition only' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'declares a non-empty GUID' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.Guid | Should -Not -Be ([Guid]::Empty)
    }
}

Describe 'RevealUI.RevStation exports' {
    BeforeAll {
        # Banner output during import goes to Information stream (6) and Host;
        # redirect both to keep test output clean.
        Import-Module $script:ManifestPath -Force -WarningAction SilentlyContinue 6> $null
    }

    AfterAll {
        Remove-Module RevealUI.RevStation -Force -ErrorAction SilentlyContinue
    }

    Context 'public functions' {
        $expectedFunctions = @(
            'Start-WSL', 'Restart-WSL', 'Mount-WSLDev', 'Get-WSLStatus', 'Get-WSLMounts',
            'Find-RevealUIDrive', 'Show-WSLHelp', 'Get-Secret', 'Sync-RevealUIToWindows',
            'Register-DevMountTask', 'Unregister-DevMountTask'
        )

        It 'exports <_>' -ForEach $expectedFunctions {
            Get-Command $_ -Module RevealUI.RevStation -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    Context 'aliases' {
        $expectedAliases = @(
            @{ Alias = 'wsls';      Func = 'Start-WSL' }
            @{ Alias = 'wslr';      Func = 'Restart-WSL' }
            @{ Alias = 'wslstat';   Func = 'Get-WSLStatus' }
            @{ Alias = 'wslmount';  Func = 'Mount-WSLDev' }
            @{ Alias = 'wslmounts'; Func = 'Get-WSLMounts' }
            @{ Alias = 'wslhelp';   Func = 'Show-WSLHelp' }
            @{ Alias = 'wslsync';   Func = 'Sync-RevealUIToWindows' }
            @{ Alias = 'secret';    Func = 'Get-Secret' }
        )

        It '<Alias> -> <Func>' -ForEach $expectedAliases {
            $a = Get-Alias $Alias -ErrorAction Stop
            $a.Definition | Should -Be $Func
        }
    }
}
