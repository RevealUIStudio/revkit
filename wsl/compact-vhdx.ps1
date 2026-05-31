# compact-vhdx.ps1 — Compact WSL VHDx to reclaim freed space on C:
# Run elevated (admin). Scheduled via WSL-VHDx-Compact task.
#
# Steps:
#   1. Run fstrim inside WSL (zeros freed blocks for efficient compaction)
#   2. Shut down WSL
#   3. Compact via diskpart
#
# Requires: Admin privileges (diskpart needs elevation)

param(
    [string]$Distro = "Ubuntu",
    [string]$VhdxPath = "C:\WSL\Ubuntu\ext4.vhdx"
)

$ErrorActionPreference = "Stop"

Write-Host "[compact-vhdx] Starting VHDx compaction for $Distro..."

# Step 1: fstrim inside WSL (best-effort — WSL may not support it)
try {
    Write-Host "[compact-vhdx] Running fstrim..."
    wsl -d $Distro -- sudo fstrim -av 2>&1 | Write-Host
} catch {
    Write-Host "[compact-vhdx] fstrim skipped (not supported or WSL not running)"
}

# Step 2: Shut down WSL
Write-Host "[compact-vhdx] Shutting down WSL..."
wsl --shutdown
Start-Sleep -Seconds 5

# Step 3: Compact via diskpart
if (-not (Test-Path $VhdxPath)) {
    Write-Error "[compact-vhdx] VHDx not found: $VhdxPath"
    exit 1
}

$diskpartScript = [System.IO.Path]::GetTempFileName()
@"
select vdisk file="$VhdxPath"
compact vdisk
detach vdisk
exit
"@ | Set-Content -Path $diskpartScript -Encoding ASCII

Write-Host "[compact-vhdx] Compacting VHDx..."
$before = (Get-Item $VhdxPath).Length
# Capture diskpart's native exit code explicitly. Under powershell.exe (the
# scheduled-task path) a non-zero native exit does NOT become a terminating
# error even with $ErrorActionPreference='Stop', so without this check a failed
# compaction (VHDx in use, diskpart error) falls through to the "Done" message
# and the weekly run reports success while doing nothing.
$diskpartOutput = diskpart /s $diskpartScript 2>&1
$diskpartExit = $LASTEXITCODE
$diskpartOutput | Write-Host
Remove-Item $diskpartScript -ErrorAction SilentlyContinue
if ($diskpartExit -ne 0) {
    throw "[compact-vhdx] diskpart exited with code $diskpartExit — compaction failed; not reporting success."
}
$after = (Get-Item $VhdxPath).Length

$freedMB = [math]::Round(($before - $after) / 1MB)
Write-Host "[compact-vhdx] Done. Freed ${freedMB} MB ($(([math]::Round($after / 1GB, 1))) GB now)"
