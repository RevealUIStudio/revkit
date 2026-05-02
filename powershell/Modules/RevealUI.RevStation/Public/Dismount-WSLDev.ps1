#Requires -Version 7.0
#Requires -PSEdition Core

function Dismount-WSLDev {
    <#
    .SYNOPSIS
        Safely ejects the Forge SSD from WSL — stops services, flushes filesystem,
        unmounts inside WSL, then detaches from Windows so the drive can be unplugged.
    .DESCRIPTION
        Performs a safe 6-step eject sequence:
          1. Stop services that hold /mnt/forge open (Postgres, Redis, Ollama)
          2. Check for remaining open file handles with lsof
          3. Flush pending writes with sync
          4. Unmount /mnt/forge inside WSL
          5. Detach the physical disk from WSL (wsl --unmount)
          6. Notify the user it is safe to unplug

        When run without elevation, self-elevates for the Windows-side unmount step.
        "Safely Remove Hardware" does NOT know about WSL mounts — always use this
        command instead of relying on Windows' own eject mechanism.
    .ALIASES
        wslunmount
    .EXAMPLE
        Dismount-WSLDev
        Dismount-WSLDev -Force    # skip lsof open-handle check
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [switch]$Force
    )

    $logDir  = Get-ModuleLogPath
    $logFile = Join-Path $logDir 'dismount-forge.log'

    # Load local-config.ps1 for hardware-specific values ($DevDriveSerial)
    $localConfig = Join-Path $PSScriptRoot '..' 'local-config.ps1'
    if (Test-Path $localConfig) {
        . (Resolve-Path $localConfig)
    }
    if (-not $DevDriveSerial) {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                'DevDriveSerial is not set. Create local-config.ps1 from local-config.example.ps1.'),
            'SerialNotConfigured',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # ── Step 0: Verify the drive is actually mounted ───────────────────────────
    $mounted = (wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/forge && echo YES || echo NO" 2>&1) -join ' '
    if ($mounted -notmatch 'YES') {
        Write-DevLog '/mnt/forge is not mounted — nothing to do.' -Source 'Dismount' -LogFile $logFile
        Write-Host '  /mnt/forge is not mounted.' -ForegroundColor DarkGray
        return
    }

    Write-DevLog 'Starting safe Forge drive eject sequence...' -Source 'Dismount' -LogFile $logFile
    Write-Host ''
    Write-Host '  Forge drive — safe eject' -ForegroundColor Cyan

    # ── Step 1: Stop services using /mnt/forge ────────────────────────────────
    Write-Host '  [1/6] Stopping services...' -ForegroundColor DarkGray
    $services = @(
        'pg_ctl stop -D /mnt/forge/.pgdata -m fast 2>/dev/null',
        'redis-cli shutdown nosave 2>/dev/null',
        'pkill -f "ollama serve" 2>/dev/null'
    )
    foreach ($svc in $services) {
        wsl.exe -d Ubuntu -e bash -c $svc 2>&1 | Out-Null
    }
    Write-DevLog 'Service stop commands sent (best-effort).' -Source 'Dismount' -LogFile $logFile

    # ── Step 2: Check for open file handles ───────────────────────────────────
    Write-Host '  [2/6] Checking for open handles...' -ForegroundColor DarkGray
    $openHandles = wsl.exe -d Ubuntu -e bash -c "lsof +D /mnt/forge 2>/dev/null | tail -n +2" 2>&1
    if ($openHandles -and $openHandles.Trim()) {
        Write-DevLog "Open handles found on /mnt/forge:`n$openHandles" -Level WARN -Source 'Dismount' -LogFile $logFile
        if (-not $Force) {
            Write-Host ''
            Write-Host '  ⚠  Open file handles detected:' -ForegroundColor Yellow
            $openHandles | Select-Object -First 10 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkYellow }
            Write-Host ''
            Write-Host '  Run  Dismount-WSLDev -Force  to eject anyway, or close the above processes first.' -ForegroundColor Yellow
            Write-Host ''
            return
        }
        Write-DevLog '-Force specified — proceeding despite open handles.' -Level WARN -Source 'Dismount' -LogFile $logFile
        Write-Host '  ⚠  Proceeding with open handles (-Force).' -ForegroundColor Yellow
    } else {
        Write-Host '     No open handles.' -ForegroundColor DarkGray
        Write-DevLog 'No open handles found on /mnt/forge.' -Source 'Dismount' -LogFile $logFile
    }

    # ── Step 3: Flush filesystem ──────────────────────────────────────────────
    Write-Host '  [3/6] Flushing filesystem...' -ForegroundColor DarkGray
    wsl.exe -d Ubuntu -e bash -c 'sync' 2>&1 | Out-Null
    Write-DevLog 'sync complete.' -Source 'Dismount' -LogFile $logFile

    # ── Step 4: Unmount inside WSL ────────────────────────────────────────────
    Write-Host '  [4/6] Unmounting /mnt/forge...' -ForegroundColor DarkGray
    if (-not $PSCmdlet.ShouldProcess('/mnt/forge', 'Unmount inside WSL')) { return }

    $umountOut = wsl.exe -d Ubuntu -e bash -c 'sudo umount /mnt/forge 2>&1' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-DevLog "umount /mnt/forge failed (exit $LASTEXITCODE): $umountOut" -Level ERROR -Source 'Dismount' -LogFile $logFile
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to unmount /mnt/forge: $umountOut"),
            'UmountFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }
    Write-DevLog '/mnt/forge unmounted.' -Source 'Dismount' -LogFile $logFile

    # ── Step 5: Detach from Windows (requires elevation) ─────────────────────
    Write-Host '  [5/6] Detaching disk from WSL...' -ForegroundColor DarkGray

    $devDisk = Get-Disk | Where-Object { $_.SerialNumber -match $DevDriveSerial }
    if (-not $devDisk) {
        Write-DevLog 'Forge disk not found in Windows — already detached.' -Level WARN -Source 'Dismount' -LogFile $logFile
        Write-Host '     Disk not found in Windows (already detached).' -ForegroundColor DarkGray
    } else {
        $driveNumber = $devDisk.Number
        Write-DevLog "Detaching PHYSICALDRIVE$driveNumber..." -Source 'Dismount' -LogFile $logFile

        if (Test-IsAdmin) {
            wsl.exe --unmount "\\.\PHYSICALDRIVE$driveNumber" 2>&1 | Out-Null
            Write-DevLog "PHYSICALDRIVE$driveNumber detached from WSL." -Source 'Dismount' -LogFile $logFile
        } else {
            if (-not $PSCmdlet.ShouldProcess("PHYSICALDRIVE$driveNumber", 'Detach from WSL (elevated)')) { return }
            $cmd = "wsl.exe --unmount '\\.\PHYSICALDRIVE$driveNumber'"
            Invoke-Elevated -Command $cmd -Wait
            Write-DevLog "PHYSICALDRIVE$driveNumber detached (elevated)." -Source 'Dismount' -LogFile $logFile
        }
    }

    # ── Step 6: Notify user ───────────────────────────────────────────────────
    Write-Host '  [6/6] Done.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  ✓ Forge drive safely ejected.' -ForegroundColor Green
    Write-Host '    It is now safe to physically unplug the drive.' -ForegroundColor DarkGray
    Write-Host ''
    Write-DevLog 'Forge drive eject sequence complete.' -Source 'Dismount' -LogFile $logFile
}
