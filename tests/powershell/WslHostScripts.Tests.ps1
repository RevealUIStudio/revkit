#Requires -Version 7.0

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Scripts = Join-Path $script:RepoRoot 'scripts'
}

Describe 'Register-WeeklyBackupTask source contract' {
    It 'exists' {
        Test-Path (Join-Path $script:Scripts 'Register-WeeklyBackupTask.ps1') | Should -BeTrue
    }

    It 'wraps the action in conhost --headless and sets WakeToRun' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Register-WeeklyBackupTask.ps1')
        $src.Contains('conhost.exe') | Should -BeTrue
        $src.Contains('--headless') | Should -BeTrue
        $src.Contains('WakeToRun') | Should -BeTrue
        $src.Contains('pwsh.exe') | Should -BeTrue
    }

    It 'does not register a bare pwsh.exe Execute' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Register-WeeklyBackupTask.ps1')
        $src.Contains("-Execute 'pwsh.exe'") | Should -BeFalse
        $src.Contains('-Execute "pwsh.exe"') | Should -BeFalse
    }

    It 'puts S4U on New-ScheduledTaskPrincipal and replaces with -Force' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Register-WeeklyBackupTask.ps1')
        $src.Contains('New-ScheduledTaskPrincipal') | Should -BeTrue
        $src.Contains('-Force') | Should -BeTrue
        $src.Contains('Unregister-ScheduledTask') | Should -BeFalse
    }
}

Describe 'Move-WslVhdx source contract' {
    It 'exists' {
        Test-Path (Join-Path $script:Scripts 'Move-WslVhdx.ps1') | Should -BeTrue
    }

    It 'uses wsl --manage --move onto E:\WSL' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Move-WslVhdx.ps1')
        $src.Contains('--manage') | Should -BeTrue
        $src.Contains('--move') | Should -BeTrue
        $src.Contains('E:\WSL\Ubuntu') | Should -BeTrue
    }

    It 'does not unregister or tar-import the distro' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Move-WslVhdx.ps1')
        $src.Contains('--unregister') | Should -BeFalse
        $src.Contains('--import') | Should -BeFalse
        $src.Contains('--export') | Should -BeFalse
    }

    It 'does not pre-create the destination directory before --move' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Move-WslVhdx.ps1')
        $moveIdx = $src.IndexOf('wsl.exe --manage')
        ($moveIdx -ge 0) | Should -BeTrue
        $before = $src.Substring(0, $moveIdx)
        $before.Contains('New-Item -ItemType Directory -Force -Path $Destination') | Should -BeFalse
        $before.Contains('Removing empty leftover') | Should -BeTrue
        $src.Contains('Join-Path $Destination ''move-vhdx.log''') | Should -BeFalse
        $src.Contains('Join-Path $Destination "move-vhdx.log"') | Should -BeFalse
    }

    It 'waits for the VHD handle to release and serializes concurrent runs' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Move-WslVhdx.ps1')
        $src.Contains('Global\RevealUI-Move-WslVhdx') | Should -BeTrue
        $src.Contains('[System.IO.FileShare]::None') | Should -BeTrue
        $src.Contains('DISTRO_NOT_STOPPED') | Should -BeTrue
        $src.Contains('VHD handle released') | Should -BeTrue
        $src.Contains('WorkingDirectory') | Should -BeTrue
    }

    It 'no-ops an already-moved VHD before UAC and before Wait-WslVhdReleased' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Move-WslVhdx.ps1')
        $alreadyIdx = $src.IndexOf('VHD already at')
        $runAsIdx = $src.IndexOf('RunAs')
        $waitCallIdx = $src.IndexOf('Wait-WslVhdReleased -VhdPath')
        ($alreadyIdx -ge 0) | Should -BeTrue
        ($runAsIdx -ge 0) | Should -BeTrue
        ($waitCallIdx -ge 0) | Should -BeTrue
        ($alreadyIdx -lt $runAsIdx) | Should -BeTrue
        ($alreadyIdx -lt $waitCallIdx) | Should -BeTrue
    }
}

Describe 'Apply-WslHostFix source contract' {
    It 'runs register then move' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Apply-WslHostFix.ps1')
        ($src.IndexOf('Register-WeeklyBackupTask.ps1') -ge 0) | Should -BeTrue
        ($src.IndexOf('Move-WslVhdx.ps1') -ge 0) | Should -BeTrue
        ($src.IndexOf('Register-WeeklyBackupTask.ps1') -lt $src.IndexOf('Move-WslVhdx.ps1')) | Should -BeTrue
    }

    It 'elevates from a Windows working directory and skips move when VHD is already on E:' {
        $src = Get-Content -Raw (Join-Path $script:Scripts 'Apply-WslHostFix.ps1')
        $src.Contains('WorkingDirectory') | Should -BeTrue
        $src.Contains('$env:TEMP') | Should -BeTrue
        $src.Contains('vhdAlreadyMoved') | Should -BeTrue
        $src.Contains('will not shut WSL down') | Should -BeTrue
        ($src.IndexOf('vhdAlreadyMoved') -lt $src.IndexOf('RunAs')) | Should -BeTrue
    }
}

Describe 'Register-VHDxCompactTask source contract' {
    It 'wraps compact in conhost --headless' {
        $src = Get-Content -Raw (Join-Path $script:RepoRoot 'shell' 'Register-VHDxCompactTask.ps1')
        $src.Contains('conhost.exe') | Should -BeTrue
        $src.Contains('--headless') | Should -BeTrue
    }
}
