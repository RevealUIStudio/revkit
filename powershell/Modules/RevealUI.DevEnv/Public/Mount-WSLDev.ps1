#Requires -Version 7.0
#Requires -PSEdition Core

function Mount-WSLDev {
    <#
    .SYNOPSIS
        Finds the dev SSD by serial number, attaches it to WSL, and mounts at /mnt/wsl-dev.
    .DESCRIPTION
        All mount logic is inline — no external script dependency. When run without elevation,
        self-elevates via pwsh.exe with module discovery. Includes WSL readiness polling,
        retry loop for wsl --mount, and block device wait.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [switch]$SkipWait,

        [ValidateSet('logon', 'usb', 'periodic', 'scheduled', 'manual')]
        [string]$TriggerSource = 'manual'
    )

    $logDir = Get-ModuleLogPath
    $logFile = Join-Path $logDir 'mount-wsl-dev.log'
    $DevDriveSerial = 'WXB2A91FA77H'

    # --- Self-elevation if not admin ---
    if (-not (Test-IsAdmin)) {
        if (-not $PSCmdlet.ShouldProcess('Mount-WSLDev', 'Elevate to administrator')) {
            return
        }
        Write-DevLog 'Elevating to mount dev drive...' -Level WARN -Source 'Mount' -LogFile $logFile
        $cmd = "Mount-WSLDev -SkipWait -TriggerSource $TriggerSource"
        Invoke-Elevated -Command $cmd -Wait

        # Verify from non-elevated session
        Write-DevLog 'Checking mount status...' -Source 'Mount' -LogFile $logFile
        $status = wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/wsl-dev && echo 'YOURMOUNT_YES' || echo 'YOURMOUNT_NO'" 2>&1
        if ($status -match 'YOURMOUNT_YES') {
            Write-DevLog 'Dev drive: MOUNTED' -Source 'Mount' -LogFile $logFile
        } else {
            Write-DevLog 'Dev drive: NOT MOUNTED' -Level ERROR -Source 'Mount' -LogFile $logFile
        }
        return
    }

    # --- Running elevated from here ---

    # Wait for system stabilization (skip when called from Restart-WSL or scheduled)
    if (-not $SkipWait) {
        Write-DevLog 'Waiting for system stabilization (8s)...' -Source 'Mount' -LogFile $logFile
        Start-Sleep -Seconds 8
    }

    # --- Check if already mounted ---
    $mountCheck = (wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/wsl-dev && echo YOURMOUNT_YES || echo YOURMOUNT_NO" 2>&1) -join ' '
    if ($mountCheck -match 'YOURMOUNT_YES') {
        Write-DevLog 'Dev drive already mounted at /mnt/wsl-dev' -Source 'Mount' -LogFile $logFile
        return
    }

    # --- Handle WSL not ready ---
    if ($mountCheck -match 'WSL_E_|Wsl/|not running|not found') {
        Write-DevLog "WSL not ready: $mountCheck" -Level WARN -Source 'Mount' -LogFile $logFile
        Write-DevLog 'Waiting for WSL to become available...' -Source 'Mount' -LogFile $logFile
        $wslReady = $false
        for ($i = 1; $i -le 6; $i++) {
            Start-Sleep -Seconds 5
            $check = wsl.exe -d Ubuntu -e echo READY 2>&1
            if ($check -match 'READY') {
                $wslReady = $true
                Write-DevLog "WSL ready after $($i * 5)s" -Source 'Mount' -LogFile $logFile
                break
            }
        }
        if (-not $wslReady) {
            Write-DevLog 'WSL did not become available after 30s. Aborting.' -Level ERROR -Source 'Mount' -LogFile $logFile
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.TimeoutException]::new('WSL did not become available after 30s'),
                'WSLTimeout', [System.Management.Automation.ErrorCategory]::ResourceUnavailable, $null)
            $PSCmdlet.ThrowTerminatingError($err)
        }
    }

    # --- Find the dev drive by serial number ---
    $devDisk = Get-Disk | Where-Object { $_.SerialNumber -match $DevDriveSerial }

    if (-not $devDisk) {
        Write-DevLog "Dev drive not found (serial: $DevDriveSerial). Is it plugged in?" -Level WARN -Source 'Mount' -LogFile $logFile
        return  # Not an error — drive simply not connected
    }

    $driveNumber = $devDisk.Number
    Write-DevLog "Found dev drive at PHYSICALDRIVE$driveNumber (Status: $($devDisk.OperationalStatus))" -Source 'Mount' -LogFile $logFile

    if (-not $PSCmdlet.ShouldProcess("PHYSICALDRIVE$driveNumber", 'Attach and mount to WSL')) {
        return
    }

    # --- Clean up any stale attachment ---
    wsl.exe --unmount "\\.\PHYSICALDRIVE$driveNumber" 2>&1 | Out-Null

    # --- Attach with retry ---
    $maxRetries = 3
    $attached = $false

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        Write-DevLog "Attaching PHYSICALDRIVE$driveNumber to WSL (attempt $attempt/$maxRetries)..." -Source 'Mount' -LogFile $logFile
        $attachOutput = wsl.exe --mount "\\.\PHYSICALDRIVE$driveNumber" --bare 2>&1

        if ($LASTEXITCODE -eq 0) {
            $attached = $true
            Write-DevLog 'Disk attached successfully' -Source 'Mount' -LogFile $logFile
            break
        }

        Write-DevLog "Attach attempt $attempt failed (exit $LASTEXITCODE): $attachOutput" -Level WARN -Source 'Mount' -LogFile $logFile

        if ($attempt -lt $maxRetries) {
            Write-DevLog 'Retrying in 5s...' -Source 'Mount' -LogFile $logFile
            Start-Sleep -Seconds 5
            wsl.exe --unmount "\\.\PHYSICALDRIVE$driveNumber" 2>&1 | Out-Null
        }
    }

    if (-not $attached) {
        Write-DevLog "Failed to attach dev drive after $maxRetries attempts" -Level ERROR -Source 'Mount' -LogFile $logFile
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to attach PHYSICALDRIVE$driveNumber after $maxRetries attempts"),
            'AttachFailed', [System.Management.Automation.ErrorCategory]::ResourceUnavailable, $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # --- Wait for block device to appear in WSL ---
    Write-DevLog 'Waiting for block device to appear in WSL...' -Source 'Mount' -LogFile $logFile
    $deviceReady = $false
    for ($i = 1; $i -le 10; $i++) {
        Start-Sleep -Seconds 1
        $blkCheck = wsl.exe -d Ubuntu -e bash -c "blkid -L WSL-Dev 2>/dev/null && echo FOUND || echo NOTFOUND" 2>&1
        if ($blkCheck -match 'FOUND') {
            $deviceReady = $true
            Write-DevLog "Block device detected after ${i}s" -Source 'Mount' -LogFile $logFile
            break
        }
    }

    if (-not $deviceReady) {
        Write-DevLog 'Block device did not appear after 10s. Proceeding with mount helper anyway...' -Level WARN -Source 'Mount' -LogFile $logFile
    }

    # --- Mount the partition inside WSL ---
    Write-DevLog 'Mounting partition inside WSL at /mnt/wsl-dev...' -Source 'Mount' -LogFile $logFile
    $wslResult = wsl.exe -d Ubuntu -e sudo /usr/local/bin/mount-dev-drive.sh 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-DevLog "WSL mount helper failed (exit $LASTEXITCODE): $wslResult" -Level ERROR -Source 'Mount' -LogFile $logFile
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("WSL mount helper failed (exit $LASTEXITCODE): $wslResult"),
            'MountHelperFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # --- Verify ---
    $verify = (wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/wsl-dev && echo SUCCESS || echo FAILED" 2>&1) -join ' '
    if ($verify -match 'SUCCESS') {
        Write-DevLog 'WSL dev drive mounted successfully at /mnt/wsl-dev' -Source 'Mount' -LogFile $logFile
    } else {
        Write-DevLog 'Mount verification failed' -Level ERROR -Source 'Mount' -LogFile $logFile
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Mount verification failed — /mnt/wsl-dev not mounted'),
            'VerifyFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }
}
