#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'powershell' 'Modules' 'RevealUI.RevStation'
    Import-Module (Join-Path $script:ModuleRoot 'RevealUI.RevStation.psd1') -Force 6> $null
}

AfterAll {
    Remove-Module RevealUI.RevStation -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-WslPath' {
    It 'maps a bare drive-letter root to /mnt/<letter>' {
        InModuleScope RevealUI.RevStation { ConvertTo-WslPath 'D:\.revealui' } | Should -Be '/mnt/d/.revealui'
    }

    It 'preserves intermediate segments (professional root)' {
        InModuleScope RevealUI.RevStation { ConvertTo-WslPath 'D:\professional\.revealui' } |
            Should -Be '/mnt/d/professional/.revealui'
    }

    It 'maps a multi-segment home-style root' {
        InModuleScope RevealUI.RevStation { ConvertTo-WslPath 'C:\dev\.revealui' } |
            Should -Be '/mnt/c/dev/.revealui'
    }

    It 'lowercases the drive letter but preserves segment casing' {
        InModuleScope RevealUI.RevStation { ConvertTo-WslPath 'F:\Foo\Bar' } | Should -Be '/mnt/f/Foo/Bar'
    }

    It 'trims a trailing backslash' {
        InModuleScope RevealUI.RevStation { ConvertTo-WslPath 'D:\.revealui\' } | Should -Be '/mnt/d/.revealui'
    }

    It 'throws on a non-drive-letter (UNC) path' {
        { InModuleScope RevealUI.RevStation { ConvertTo-WslPath '\\server\share' } } | Should -Throw
    }
}
