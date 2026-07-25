# weekly-wsl-backup.ps1
# Exports the Ubuntu WSL distro to E:\backups\wsl-snapshots\current\, rotating
# older snapshots (keeps the $KeepCount most recent). Designed to be run by a
# weekly Windows scheduled task (RevealUI-WSL-Weekly-Backup, Sunday 03:00).
#
# Created 2026-04-24 during storage-recovery session.
# Replaces the dead RevealUI-Repo-Sync scheduled task role.
#
# GAP-301 (2026-07-24 re-verify): LastTaskResult 0x40 (64) on the 2026-07-19
# 03:00 run with NO backup.log lines is the host-sleep kill class. The installed
# operator copy already carried ES_SYSTEM_REQUIRED during export; this SSOT
# port keeps that + logs a TEMP bootstrap line before any E: I/O so a kill
# still leaves a fingerprint. Owner should also set WakeToRun=true on the
# scheduled task (currently false) so a sleeping host actually wakes for 03:00.

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [string]$SnapshotDir = 'E:\backups\wsl-snapshots\current',
  [int]$KeepCount = 4
)

$ErrorActionPreference = 'Stop'
$logFile = Join-Path $SnapshotDir 'backup.log'
$fallbackLog = Join-Path $env:TEMP 'wsl-backup-fallback.log'

# Keep the host awake for the duration of the export. The unattended Sunday 03:00
# run has been interrupted by system sleep on the large (150 GB+) export - the
# process dies mid-write before the size-check/catch can run, leaving a truncated
# tar with no error line (task result 0x40). ES_SYSTEM_REQUIRED resets the idle
# timer so the machine cannot sleep while wsl --export streams.
Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@ -ErrorAction SilentlyContinue
$script:ES_CONTINUOUS      = [uint32]0x80000000L  # L-suffix required: bare 0x80000000 parses as Int32 -2147483648 and fails the [uint32] cast at runtime
$script:ES_SYSTEM_REQUIRED = [uint32]0x00000001
function Set-SystemKeepAwake {
  try { [void][Win32.Power]::SetThreadExecutionState([uint32]($script:ES_CONTINUOUS -bor $script:ES_SYSTEM_REQUIRED)) } catch {}
}
function Clear-SystemKeepAwake {
  try { [void][Win32.Power]::SetThreadExecutionState([uint32]$script:ES_CONTINUOUS) } catch {}
}

function Write-Bootstrap {
  # Always-on TEMP fingerprint so a kill before E: is writable still leaves a trail.
  param([string]$Message)
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [BOOT] $Message"
  Write-Host $line
  try {
    Add-Content -Path $fallbackLog -Value $line -ErrorAction SilentlyContinue
  } catch {
    # last-resort: ignore
  }
}

function Write-Log {
  param([string]$Level, [string]$Message)
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
  Write-Host $line
  # Try the primary log on E:. If that fails (drive asleep, disconnected, locked),
  # fall back to %TEMP%. Silent drops are how this script went 3 weeks without
  # surfacing the truncated-tar failure on 2026-05-10. Never lose an error line.
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
  # TEMP bootstrap BEFORE any E: / WSL work so 0x40 kills still leave evidence.
  Write-Bootstrap "weekly-wsl-backup starting (pid=$PID distro=$Distro keep=$KeepCount)"
  Set-SystemKeepAwake
  Write-Bootstrap 'Sleep inhibited (ES_SYSTEM_REQUIRED) for entire backup run'

  # Ensure destination exists
  if (-not (Test-Path $SnapshotDir)) {
    New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
    Write-Log 'INFO' "Created $SnapshotDir"
  }

  # Verify destination drive has enough space (need ~1.5x vhdx size for headroom)
  $vhdxPath = "C:\WSL\$Distro\ext4.vhdx"
  $vhdxSizeGB = 0
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

  # Pre-export sweep: a prior run KILLED mid-export (host sleep / power loss) never
  # reaches the post-export size-check/catch below, so its truncated tar is left in
  # place and would be picked as "newest" by the freshness monitor AND count toward
  # KeepCount during rotation, evicting a good snapshot. Quarantine any existing
  # sub-floor tar (same 25%-of-vhdx / 1 GB floor the size-check uses) first.
  $preSweepFloorGB = [math]::Max(1.0, $vhdxSizeGB * 0.25)
  Get-ChildItem $SnapshotDir -Filter "$Distro-*.tar" -ErrorAction SilentlyContinue |
    Where-Object { ($_.Length / 1GB) -lt $preSweepFloorGB } |
    ForEach-Object {
      Write-Log 'WARN' "Pre-export sweep: quarantining sub-floor tar $($_.Name) ($([math]::Round($_.Length/1GB,2)) GB < $([math]::Round($preSweepFloorGB,2)) GB)"
      Move-ToFailed $_.FullName
    }

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
  Write-Bootstrap 'weekly-wsl-backup SUCCESS'
  exit 0
}
catch {
  Write-Bootstrap "weekly-wsl-backup FAILED: $($_.Exception.Message)"
  Write-Log 'ERROR' "Backup failed: $($_.Exception.Message)"
  Write-Log 'ERROR' $_.ScriptStackTrace
  exit 1
}
finally {
  Clear-SystemKeepAwake
}
