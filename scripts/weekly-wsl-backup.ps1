# weekly-wsl-backup.ps1
# Exports the Ubuntu WSL distro to E:\backups\wsl-snapshots\current\, rotating
# older snapshots (keeps the 2 most recent). Designed to be run by a weekly
# Windows scheduled task.
#
# Created 2026-04-24 during storage-recovery session.
# Replaces the dead RevealUI-Repo-Sync scheduled task role.

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [string]$SnapshotDir = 'E:\backups\wsl-snapshots\current',
  [int]$KeepCount = 2
)

$ErrorActionPreference = 'Stop'
$logFile = Join-Path $SnapshotDir 'backup.log'

function Write-Log {
  param([string]$Level, [string]$Message)
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
  Write-Host $line
  # Try the primary log on E:. If that fails (drive asleep, disconnected, locked),
  # fall back to %TEMP%. Silent drops are how this script went 3 weeks without
  # surfacing the truncated-tar failure on 2026-05-10. Never lose an error line.
  $fallbackLog = Join-Path $env:TEMP 'wsl-backup-fallback.log'
  try {
    if (Test-Path (Split-Path $logFile -Parent)) {
      Add-Content -Path $logFile -Value $line -ErrorAction Stop
    } else {
      throw "Log parent dir missing: $(Split-Path $logFile -Parent)"
    }
  } catch {
    Add-Content -Path $fallbackLog -Value "$line  (primary log unavailable: $($_.Exception.Message))" -ErrorAction SilentlyContinue
  }
}

function Move-ToFailed {
  param([string]$Path)
  # Quarantine a bad/partial export into a `failed/` subdirectory: preserved for
  # inspection but excluded from BOTH the "$Distro-*.tar" rotation glob below and
  # the staleness freshness check (both non-recursive on $SnapshotDir). Without
  # this, a preserved bad tar is counted as a recent snapshot and can evict a
  # good one during rotation (KeepCount), shrinking the usable recovery set.
  if (-not (Test-Path $Path)) { return }
  try {
    $failedDir = Join-Path $SnapshotDir 'failed'
    New-Item -ItemType Directory -Force -Path $failedDir | Out-Null
    Move-Item -Path $Path -Destination (Join-Path $failedDir (Split-Path $Path -Leaf)) -Force -ErrorAction Stop
    Write-Log 'WARN' "Quarantined bad export to $failedDir (excluded from rotation + freshness)"
    # Keep only the 2 most recent quarantined artifacts so failed/ can't grow unbounded.
    Get-ChildItem $failedDir -Filter "$Distro-*.tar" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
      ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
  } catch {
    Write-Log 'WARN' "Could not quarantine ${Path}: $($_.Exception.Message)"
  }
}

try {
  # Ensure destination exists
  if (-not (Test-Path $SnapshotDir)) {
    New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
    Write-Log 'INFO' "Created $SnapshotDir"
  }

  # Verify destination drive has enough space (need ~1.5x vhdx size for headroom)
  $vhdxPath = "C:\WSL\$Distro\ext4.vhdx"
  if (Test-Path $vhdxPath) {
    $vhdxSizeGB = (Get-Item $vhdxPath).Length / 1GB
    $destDrive = (Get-Item $SnapshotDir).PSDrive
    $destFreeGB = $destDrive.Free / 1GB
    $needGB = $vhdxSizeGB * 1.5
    if ($destFreeGB -lt $needGB) {
      throw "Insufficient space on $($destDrive.Name): have $([math]::Round($destFreeGB,1)) GB free, need ~$([math]::Round($needGB,1)) GB"
    }
    Write-Log 'INFO' "vhdx $([math]::Round($vhdxSizeGB,1)) GB, dest free $([math]::Round($destFreeGB,1)) GB"
  }

  # Shutdown WSL for clean snapshot
  Write-Log 'INFO' 'Shutting down WSL for clean snapshot'
  & wsl.exe --shutdown
  Start-Sleep -Seconds 5

  # Export with timestamp
  $stamp = Get-Date -Format 'yyyy-MM-dd-HHmm'
  $target = Join-Path $SnapshotDir "$Distro-$stamp.tar"
  Write-Log 'INFO' "Exporting $Distro -> $target"

  $exportStart = Get-Date
  & wsl.exe --export $Distro $target
  $exitCode = $LASTEXITCODE
  $exportDuration = (Get-Date) - $exportStart

  if ($exitCode -ne 0) {
    Move-ToFailed $target   # quarantine any partial tar (host interruption / out-of-space)
    throw "wsl --export exited with code $exitCode"
  }

  if (-not (Test-Path $target)) {
    throw "Export completed but target file not found: $target"
  }

  $targetSizeGB = (Get-Item $target).Length / 1GB

  # Sanity check: a healthy export is at least 1 GB AND at least 25% of the
  # vhdx size on disk. wsl --export has been observed to return exit 0 after
  # producing a truncated or 0-byte tar (2026-04-26: 18 GB; 2026-05-10: 0 B).
  # Without this check, the DR layer silently rots — fail the task explicitly
  # so the Task Scheduler LastTaskResult propagates the failure.
  $minAbsoluteGB    = 1.0
  $minRelativeRatio = 0.25
  $minRelativeGB    = if ($vhdxSizeGB) { $vhdxSizeGB * $minRelativeRatio } else { 0 }
  $minGB            = [math]::Max($minAbsoluteGB, $minRelativeGB)
  if ($targetSizeGB -lt $minGB) {
    Move-ToFailed $target
    throw "Exported tar suspiciously small: $([math]::Round($targetSizeGB,2)) GB (need >= $([math]::Round($minGB,2)) GB — $([int]($minRelativeRatio*100))% of $([math]::Round($vhdxSizeGB,1)) GB vhdx, floor $minAbsoluteGB GB). Likely a silent wsl --export failure. Bad tar quarantined under $SnapshotDir\failed\ (excluded from rotation); previous snapshots untouched."
  }

  Write-Log 'INFO' "Export complete: $([math]::Round($targetSizeGB,2)) GB in $([math]::Round($exportDuration.TotalMinutes,1)) min"

  # Rotate: keep only N most recent Ubuntu-*.tar files
  $snapshots = Get-ChildItem $SnapshotDir -Filter "$Distro-*.tar" | Sort-Object LastWriteTime -Descending
  $toDelete = $snapshots | Select-Object -Skip $KeepCount
  foreach ($old in $toDelete) {
    Write-Log 'INFO' "Rotating out: $($old.Name) ($([math]::Round($old.Length/1GB,1)) GB)"
    Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
  }

  Write-Log 'INFO' "SUCCESS - backup rotation complete, $($snapshots.Count - $toDelete.Count) snapshots retained"
  exit 0
}
catch {
  Write-Log 'ERROR' "Backup failed: $($_.Exception.Message)"
  Write-Log 'ERROR' $_.ScriptStackTrace
  exit 1
}
