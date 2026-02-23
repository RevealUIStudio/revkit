#Requires -Version 7.0
#Requires -PSEdition Core

function Get-WSLMounts {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Distribution = 'Ubuntu'
    )

    Write-Host '=== WSL Mounted Drives ===' -ForegroundColor Cyan
    wsl.exe -d $Distribution -e bash -c "mount | grep -E 'wsl|/dev/sd' | grep -v snap"
}
