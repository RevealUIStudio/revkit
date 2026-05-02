#Requires -Version 7.0
#Requires -PSEdition Core

function Write-Banner {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Detect environment
    $wslDistro = (wsl --list --quiet 2>$null | Select-Object -First 1) -replace '\x00',''
    $eDrive = if (Test-Path "E:\") { "E: mounted" } else { "E: disconnected" }
    $eDriveColor = if (Test-Path "E:\") { "Green" } else { "Yellow" }

    Write-Host "`nRevealUI RevStation " -ForegroundColor Green -NoNewline
    Write-Host "v1.0" -ForegroundColor DarkGray
    Write-Host "WSL: " -NoNewline
    Write-Host "$wslDistro" -ForegroundColor Cyan -NoNewline
    Write-Host " · " -NoNewline
    Write-Host "$eDrive" -ForegroundColor $eDriveColor
    Write-Host 'Commands: ' -NoNewline
    Write-Host 'wsls' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslr' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslstat' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslmount' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslsync' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'secret' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslhelp' -ForegroundColor Yellow
    Write-Host ""
}
