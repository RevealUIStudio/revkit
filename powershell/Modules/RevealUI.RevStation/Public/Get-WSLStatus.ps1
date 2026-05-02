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

    Write-Host "`n=== Forge Drive Status ===" -ForegroundColor Cyan
    $devMountRaw = wsl.exe -d $Distribution -e bash -c "mountpoint -q /mnt/forge && echo MOUNTED || echo NOT_MOUNTED" 2>&1
    $devMounted = $devMountRaw -match 'MOUNTED' -and $devMountRaw -notmatch 'NOT_MOUNTED'

    if ($devMounted) {
        Write-Host '  /mnt/forge: MOUNTED' -ForegroundColor Green
        wsl.exe -d $Distribution -e bash -c "df -h /mnt/forge | tail -1"
    } else {
        Write-Host '  /mnt/forge: NOT MOUNTED' -ForegroundColor Yellow
    }

    Write-Host "`n=== Systemd Status ===" -ForegroundColor Cyan
    $systemdRaw = wsl.exe -d $Distribution -e systemctl --user is-system-running 2>&1
    Write-Host "  $systemdRaw"

    # ── Health Monitor ────────────────────────────────────────────
    Write-Host "`n=== Health Monitor ===" -ForegroundColor Cyan
    $healthState = $null
    $logDir = Get-ModuleLogPath
    $stateFile = Join-Path $logDir 'wsl-health-state.json'

    if (Test-Path $stateFile) {
        try {
            $healthState = Get-Content $stateFile -Raw | ConvertFrom-Json
            $lastCheck = if ($healthState.lastCheckTime) {
                $parsed = [datetime]::Parse($healthState.lastCheckTime)
                $ago = [math]::Round(((Get-Date).ToUniversalTime() - $parsed).TotalMinutes, 0)
                "${ago}m ago"
            } else { 'never' }

            $status = if ($healthState.lastHealthy) { 'Healthy' } else { 'Unhealthy' }
            $statusColor = if ($healthState.lastHealthy) { 'Green' } else { 'Red' }
            Write-Host "  Status:    " -NoNewline
            Write-Host $status -ForegroundColor $statusColor -NoNewline
            Write-Host " (last check $lastCheck)"
            Write-Host "  Failures:  $($healthState.consecutiveFailures)"

            if ($healthState.lastRecoveryTime) {
                $recParsed = [datetime]::Parse($healthState.lastRecoveryTime)
                $recAgo = [math]::Round(((Get-Date).ToUniversalTime() - $recParsed).TotalHours, 1)
                Write-Host "  Recovery:  ${recAgo}h ago"
            } else {
                Write-Host '  Recovery:  none'
            }
        }
        catch {
            Write-Host '  State file corrupt' -ForegroundColor Yellow
        }
    }
    else {
        Write-Host '  No health data (monitor not yet run)' -ForegroundColor Yellow
    }

    $healthTask = Get-ScheduledTask -TaskName 'WSL-Health-Monitor' -ErrorAction SilentlyContinue
    if ($healthTask) {
        $taskState = $healthTask.State
        $taskColor = if ($taskState -eq 'Ready' -or $taskState -eq 'Running') { 'Green' } else { 'Yellow' }
        Write-Host "  Task:      " -NoNewline
        Write-Host "WSL-Health-Monitor ($taskState)" -ForegroundColor $taskColor
    }
    else {
        Write-Host '  Task:      not registered' -ForegroundColor Yellow
    }

    Write-Host ''

    # Return structured object for pipeline use
    [PSCustomObject]@{
        Distribution  = $Distribution
        Tier          = $tier
        DevMounted    = $devMounted
        SystemdStatus = ($systemdRaw -join '').Trim()
        HealthStatus  = if ($healthState) { if ($healthState.lastHealthy) { 'Healthy' } else { 'Unhealthy' } } else { 'Unknown' }
    }
}
