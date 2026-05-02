#Requires -Version 7.0
#Requires -PSEdition Core

function Get-WSLStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Distribution = 'Ubuntu'
    )

    Write-Host "`n=== WSL Status ===" -ForegroundColor Cyan
    wsl.exe --list --verbose

    Write-Host "`n=== WSL Version ===" -ForegroundColor Cyan
    wsl.exe --status

    Write-Host "`n=== DevKit Tier ===" -ForegroundColor Cyan
    $tierRaw = wsl.exe -d $Distribution -e bash -c 'echo "${DEVKIT_TIER:-unknown}"' 2>&1
    $tier = ($tierRaw -join '').Trim()
    Write-Host "  Tier: $tier"

    Write-Host "`n=== Studio Drive Status ===" -ForegroundColor Cyan
    $devMountRaw = wsl.exe -d $Distribution -e bash -c "mountpoint -q /mnt/studio && echo MOUNTED || echo NOT_MOUNTED" 2>&1
    $devMounted = $devMountRaw -match 'MOUNTED' -and $devMountRaw -notmatch 'NOT_MOUNTED'

    if ($devMounted) {
        Write-Host '  /mnt/studio: MOUNTED' -ForegroundColor Green
        wsl.exe -d $Distribution -e bash -c "df -h /mnt/studio | tail -1"
    } else {
        Write-Host '  /mnt/studio: NOT MOUNTED' -ForegroundColor Yellow
    }

    Write-Host "`n=== Systemd Status ===" -ForegroundColor Cyan
    $systemdRaw = wsl.exe -d $Distribution -e systemctl --user is-system-running 2>&1
    Write-Host "  $systemdRaw"

    Write-Host ''

    # Return structured object for pipeline use
    [PSCustomObject]@{
        Distribution  = $Distribution
        Tier          = $tier
        DevMounted    = $devMounted
        SystemdStatus = ($systemdRaw -join '').Trim()
    }
}
