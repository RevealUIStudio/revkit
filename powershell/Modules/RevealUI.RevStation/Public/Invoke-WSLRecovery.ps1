#Requires -Version 7.0
#Requires -PSEdition Core

function Invoke-WSLRecovery {
    <#
    .SYNOPSIS
        WSL health check and auto-recovery. Called by scheduled task or manually.
    .DESCRIPTION
        Tests WSL liveness, tracks consecutive failures, and triggers automatic
        shutdown/restart when the failure threshold is met. Detects active Claude Code
        sessions before recovery and writes recovery events for session-start hook consumption.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string]$Distribution = 'Ubuntu',
        [int]$FailureThreshold = 3,
        [int]$ProbeTimeoutSeconds = 10,

        [ValidateSet('scheduled', 'manual')]
        [string]$TriggerSource = 'manual'
    )

    $logDir = Get-ModuleLogPath
    $logFile = Join-Path $logDir 'wsl-health.log'
    $stateFile = Join-Path $logDir 'wsl-health-state.json'
    $recoveryEventsFile = Join-Path $env:USERPROFILE '.claude' 'coordination' 'wsl-recovery-events.json'
    $cooldownMinutes = 10

    # ── Load state ────────────────────────────────────────────────────
    $state = @{
        consecutiveFailures = 0
        lastCheckTime       = $null
        lastRecoveryTime    = $null
        lastHealthy         = $true
    }

    if (Test-Path $stateFile) {
        try {
            $loaded = Get-Content $stateFile -Raw | ConvertFrom-Json
            $state.consecutiveFailures = [int]($loaded.consecutiveFailures ?? 0)
            $state.lastCheckTime       = $loaded.lastCheckTime
            $state.lastRecoveryTime    = $loaded.lastRecoveryTime
            $state.lastHealthy         = $loaded.lastHealthy ?? $true
        }
        catch {
            Write-DevLog "State file corrupt, reinitialising: $_" -Level WARN -Source 'Health' -LogFile $logFile
        }
    }

    # ── Skip if distro is stopped (not zombie) ────────────────────────
    $listOutput = wsl.exe --list --verbose 2>&1 | Out-String
    if ($listOutput -match "$Distribution\s+Stopped") {
        $state.consecutiveFailures = 0
        $state.lastCheckTime = (Get-Date).ToUniversalTime().ToString('o')
        $state.lastHealthy = $true
        Save-HealthState $state $stateFile
        if ($TriggerSource -eq 'manual') {
            Write-DevLog "$Distribution is stopped — not a zombie state, skipping" -Source 'Health' -LogFile $logFile
        }
        return
    }

    # ── Run health probe ──────────────────────────────────────────────
    $probe = Test-WSLHealth -Distribution $Distribution -TimeoutSeconds $ProbeTimeoutSeconds

    $state.lastCheckTime = (Get-Date).ToUniversalTime().ToString('o')

    if ($probe.Healthy) {
        if (-not $state.lastHealthy) {
            Write-DevLog "WSL recovered naturally ($($probe.DurationMs)ms)" -Source 'Health' -LogFile $logFile
        }
        elseif ($TriggerSource -eq 'manual') {
            Write-DevLog "WSL healthy ($($probe.DurationMs)ms)" -Source 'Health' -LogFile $logFile
        }
        $state.consecutiveFailures = 0
        $state.lastHealthy = $true
        Save-HealthState $state $stateFile
        return
    }

    # ── Unhealthy ─────────────────────────────────────────────────────
    $state.consecutiveFailures++
    $state.lastHealthy = $false

    if ($state.consecutiveFailures -lt $FailureThreshold) {
        Write-DevLog "WSL health check failed ($($state.consecutiveFailures)/$FailureThreshold): $($probe.Error) — $($probe.Detail)" -Level WARN -Source 'Health' -LogFile $logFile
        Save-HealthState $state $stateFile
        return
    }

    # ── Cooldown check ────────────────────────────────────────────────
    if ($state.lastRecoveryTime) {
        $lastRecovery = [datetime]::Parse($state.lastRecoveryTime)
        $minutesSince = ((Get-Date).ToUniversalTime() - $lastRecovery).TotalMinutes
        if ($minutesSince -lt $cooldownMinutes) {
            Write-DevLog "Recovery cooldown active ($([math]::Round($minutesSince, 1))min since last recovery, need ${cooldownMinutes}min)" -Level WARN -Source 'Health' -LogFile $logFile
            Save-HealthState $state $stateFile
            return
        }
    }

    Write-DevLog "WSL zombie detected — $($state.consecutiveFailures) consecutive failures. Starting recovery..." -Level ERROR -Source 'Health' -LogFile $logFile

    # ── Pre-recovery: detect Claude sessions ──────────────────────────
    $claudeSession = @{ detected = $false }

    # Try UNC path (9P filesystem may work even when wsl.exe commands fail)
    $beaconPath = "\\wsl$\$Distribution\home\joshua-v-dev\.claude\coordination\context-beacon.json"
    try {
        if (Test-Path $beaconPath) {
            $beacon = Get-Content $beaconPath -Raw | ConvertFrom-Json
            if ($beacon.sessionActive) {
                $claudeSession.detected = $true
                $claudeSession.activeProject = $beacon.activeProject
                $claudeSession.activeBranch = $beacon.activeBranch
                Write-DevLog "Active Claude session detected: project=$($beacon.activeProject), branch=$($beacon.activeBranch)" -Level WARN -Source 'Health' -LogFile $logFile
            }
        }
    }
    catch {
        Write-DevLog "Could not read WSL beacon via UNC: $_" -Level DEBUG -Source 'Health' -LogFile $logFile
    }

    # Try reading session files for session ID
    $sessionDir = "\\wsl$\$Distribution\home\joshua-v-dev\.claude\sessions"
    try {
        if (Test-Path $sessionDir) {
            $sessionFiles = Get-ChildItem $sessionDir -Filter '*.json' -ErrorAction SilentlyContinue
            foreach ($sf in $sessionFiles) {
                try {
                    $sess = Get-Content $sf.FullName -Raw | ConvertFrom-Json
                    if ($sess.sessionId) {
                        $claudeSession.sessionId = $sess.sessionId
                        Write-DevLog "Found WSL Claude session ID: $($sess.sessionId)" -Source 'Health' -LogFile $logFile
                        break
                    }
                }
                catch { }
            }
        }
    }
    catch {
        Write-DevLog "Could not read WSL session files: $_" -Level DEBUG -Source 'Health' -LogFile $logFile
    }

    # ── Recovery: shutdown ────────────────────────────────────────────
    Write-DevLog 'Shutting down WSL...' -Source 'Health' -LogFile $logFile
    wsl --shutdown 2>&1 | Out-Null
    Start-Sleep -Seconds 5

    # ── Recovery: restart + verify ────────────────────────────────────
    Write-DevLog 'Restarting WSL...' -Source 'Health' -LogFile $logFile
    wsl.exe -d $Distribution -e true 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    $verifyProbe = Test-WSLHealth -Distribution $Distribution -TimeoutSeconds $ProbeTimeoutSeconds
    $recoverySucceeded = $verifyProbe.Healthy

    if ($recoverySucceeded) {
        Write-DevLog "WSL recovery succeeded ($($verifyProbe.DurationMs)ms)" -Source 'Health' -LogFile $logFile
    }
    else {
        Write-DevLog "WSL recovery FAILED: $($verifyProbe.Error) — $($verifyProbe.Detail)" -Level ERROR -Source 'Health' -LogFile $logFile
    }

    # ── Write recovery event ──────────────────────────────────────────
    $event = @{
        timestamp            = (Get-Date).ToUniversalTime().ToString('o')
        distribution         = $Distribution
        consecutiveFailures  = $state.consecutiveFailures
        triggerSource        = $TriggerSource
        recoverySucceeded    = $recoverySucceeded
        claudeSession        = $claudeSession
    }

    try {
        $coordDir = Split-Path $recoveryEventsFile
        if (-not (Test-Path $coordDir)) {
            New-Item -ItemType Directory -Path $coordDir -Force | Out-Null
        }

        $events = @()
        if (Test-Path $recoveryEventsFile) {
            try {
                $existing = Get-Content $recoveryEventsFile -Raw | ConvertFrom-Json
                $events = @($existing.events)
            }
            catch { }
        }

        $events += $event

        # Keep only last 50 events
        if ($events.Count -gt 50) {
            $events = $events[-50..-1]
        }

        # Atomic write: temp file then rename
        $tempFile = "$recoveryEventsFile.tmp"
        @{ events = $events } | ConvertTo-Json -Depth 5 | Set-Content $tempFile -Encoding utf8NoBOM
        Move-Item $tempFile $recoveryEventsFile -Force

        Write-DevLog 'Recovery event written' -Source 'Health' -LogFile $logFile
    }
    catch {
        Write-DevLog "Failed to write recovery event: $_" -Level WARN -Source 'Health' -LogFile $logFile
    }

    # ── Best-effort Forge drive re-mount ─────────────────────────────
    if ($recoverySucceeded -and (Test-IsAdmin)) {
        try {
            Write-DevLog 'Re-mounting Forge drive...' -Source 'Health' -LogFile $logFile
            Mount-WSLDev -TriggerSource scheduled
        }
        catch {
            Write-DevLog "Forge drive re-mount failed (mount task will retry): $_" -Level WARN -Source 'Health' -LogFile $logFile
        }
    }

    # ── Update state ──────────────────────────────────────────────────
    $state.consecutiveFailures = 0
    $state.lastRecoveryTime = (Get-Date).ToUniversalTime().ToString('o')
    $state.lastHealthy = $recoverySucceeded
    Save-HealthState $state $stateFile
}

# ── Helper: persist state file (atomic write) ─────────────────────────
function Save-HealthState {
    param(
        [hashtable]$State,
        [string]$Path
    )

    try {
        $dir = Split-Path $Path
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $tempFile = "$Path.tmp"
        $State | ConvertTo-Json -Depth 3 | Set-Content $tempFile -Encoding utf8NoBOM
        Move-Item $tempFile $Path -Force
    }
    catch {
        # Non-fatal — next run will reinitialise
    }
}
