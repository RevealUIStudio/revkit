function Mount-WSLDev {
    [CmdletBinding()]
    param()

    $mountScript = if ($env:REVEALUI_ROOT) {
        Join-Path $env:REVEALUI_ROOT "scripts\mount-wsl-dev.ps1"
    } else {
        $null
    }

    # Fallback to legacy location
    if (-not $mountScript -or -not (Test-Path $mountScript)) {
        $mountScript = "C:\Scripts\mount-wsl-dev.ps1"
    }

    if (-not (Test-Path $mountScript)) {
        Write-Error "Mount script not found. Is the RevealUI SSD connected?"
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Host "Running mount script (elevated)..." -ForegroundColor Cyan
        & $mountScript -SkipWait
    } else {
        Write-Host "Elevating to mount dev drive..." -ForegroundColor Yellow
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", $mountScript,
            "-SkipWait"
        ) -Wait
        Write-Host "Checking mount status..." -ForegroundColor Cyan
        $status = wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/wsl-dev && echo 'MOUNTED' || echo 'NOT MOUNTED'" 2>&1
        $color = if ($status -match "MOUNTED" -and $status -notmatch "NOT") { "Green" } else { "Red" }
        Write-Host "Dev drive: $status" -ForegroundColor $color
    }
}
