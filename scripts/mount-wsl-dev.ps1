# WSL Development Drive Auto-Mount
# Requires Admin privileges
# Finds the dev drive by serial number, attaches it to WSL, and mounts inside WSL

param(
    [switch]$SkipWait  # Skip initial delay (used when called from Restart-WSL)
)

# --- Logging ---
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "mount-wsl-dev.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $Message -ForegroundColor $Color
}

# --- Wait for system stabilization ---
if (-not $SkipWait) {
    Start-Sleep -Seconds 8
}

# --- Check if already mounted ---
# Join output to a single string to avoid PowerShell array -match quirks
$mountCheck = (wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/wsl-dev && echo YOURMOUNT_YES || echo YOURMOUNT_NO" 2>&1) -join " "
if ($mountCheck -match "YOURMOUNT_YES") {
    Write-Log "Dev drive already mounted at /mnt/wsl-dev" "Green"
    exit 0
}

# --- Find the dev drive by serial number ---
$devDisk = Get-Disk | Where-Object { $_.SerialNumber -match 'WXB2A91FA77H' }

if (-not $devDisk) {
    Write-Log "Dev drive not found (WD My Passport - DevBox). Is it plugged in?" "Red"
    exit 1
}

$driveNumber = $devDisk.Number
Write-Log "Found dev drive at PHYSICALDRIVE$driveNumber"

# --- Clean up any stale attachment ---
wsl.exe --unmount "\\.\PHYSICALDRIVE$driveNumber" 2>&1 | Out-Null

# --- Attach the physical drive to WSL in bare mode ---
Write-Log "Attaching PHYSICALDRIVE$driveNumber to WSL (bare mode)..."
$attachOutput = wsl.exe --mount "\\.\PHYSICALDRIVE$driveNumber" --bare 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Log "Failed to attach dev drive (exit code $LASTEXITCODE): $attachOutput" "Red"
    exit 1
}

Write-Log "Disk attached. Waiting for device to appear..."
Start-Sleep -Seconds 2

# --- Pre-initialize WSL to start systemd ---
wsl.exe -d Ubuntu -e true 2>&1 | Out-Null
Start-Sleep -Seconds 3

# --- Mount the partition inside WSL ---
Write-Log "Mounting partition inside WSL at /mnt/wsl-dev..."
$wslResult = wsl.exe -d Ubuntu -e sudo /usr/local/bin/mount-dev-drive.sh 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Log "WSL mount helper failed: $wslResult" "Red"
    # Fallback: try direct mount of common device names
    Write-Log "Trying fallback mount..." "Yellow"
    $fallbackResult = wsl.exe -d Ubuntu -e bash -c "for dev in /dev/sdd1 /dev/sdc1 /dev/sdb1; do if [ -b `$dev ]; then sudo mount -t ext4 -o defaults,noatime `$dev /mnt/wsl-dev 2>/dev/null && echo SUCCESS && exit 0; fi; done; echo FAILED" 2>&1
    if ($fallbackResult -notmatch "SUCCESS") {
        Write-Log "All mount attempts failed" "Red"
        exit 1
    }
}

# --- Verify ---
$verify = wsl.exe -d Ubuntu -e bash -c "mountpoint -q /mnt/wsl-dev && echo SUCCESS || echo FAILED" 2>&1
if ($verify -match "SUCCESS") {
    Write-Log "WSL dev drive mounted successfully at /mnt/wsl-dev" "Green"
} else {
    Write-Log "Mount verification failed" "Red"
    exit 1
}
