# check-backup-staleness.ps1
# Surfaces a Windows Application Event Log warning when the newest WSL backup
# snapshot is older than $MaxAgeDays. Designed to run from the existing
# WSL-Health-Monitor scheduled task (every 3 min) so silent failures of
# RevealUI-WSL-Weekly-Backup get caught within minutes of becoming stale.
#
# Created 2026-05-30 in response to the 3-week silent failure of the
# 2026-05-17 and 2026-05-24 backup runs (LastTaskResult: 1, no log entries).
# Same failure pattern as RevealUI-Repo-Sync (May 2026). This is the
# generalized fix — surface the *class* of failure, not just this instance.

[CmdletBinding()]
param(
  [string]$SnapshotDir = 'E:\backups\wsl-snapshots\current',
  [string]$Pattern = 'Ubuntu-*.tar',
  [int]$MaxAgeDays = 10,
  [string]$EventSource = 'RevealUI-Health',
  [int]$EventId = 9100
)

$ErrorActionPreference = 'Stop'

# Ensure the event source exists. Creating it requires admin once; subsequent
# writes work from any context. Swallow the create error if it already exists
# or if the current context lacks admin (it will fall back to Write-Host below).
try {
  if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName Application -Source $EventSource -ErrorAction Stop
  }
} catch {
  # Source may already exist on another log, or we lack admin. Carry on.
}

function Write-Health {
  param([string]$EntryType, [string]$Message)
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "$stamp [$EntryType] $Message"
  Write-Host $line
  # Primary: Application event log (requires source registered once with admin).
  # Use System.Diagnostics.EventLog directly — Write-EventLog is Windows
  # PowerShell 5.1 only, removed in PowerShell 7+, and this script runs in pwsh.
  try {
    $entryTypeEnum = [System.Diagnostics.EventLogEntryType]::$EntryType
    [System.Diagnostics.EventLog]::WriteEntry($EventSource, $Message, $entryTypeEnum, $EventId)
  } catch {
    # Fallback: append to a known log file so non-admin contexts still leave
    # a trail. Path matches the weekly-backup script's own log directory for
    # discoverability.
    $fallback = 'E:\backups\wsl-snapshots\current\health.log'
    try {
      $parent = Split-Path $fallback -Parent
      if (Test-Path $parent) {
        Add-Content -Path $fallback -Value $line -ErrorAction Stop
      } else {
        Add-Content -Path (Join-Path $env:TEMP 'wsl-backup-health.log') -Value $line -ErrorAction SilentlyContinue
      }
    } catch {
      Add-Content -Path (Join-Path $env:TEMP 'wsl-backup-health.log') -Value $line -ErrorAction SilentlyContinue
    }
  }
}

if (-not (Test-Path $SnapshotDir)) {
  Write-Health -EntryType 'Error' -Message "WSL backup snapshot dir missing: $SnapshotDir"
  exit 1
}

$newest = Get-ChildItem $SnapshotDir -Filter $Pattern -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $newest) {
  Write-Health -EntryType 'Error' -Message "No WSL backup snapshots found in $SnapshotDir matching $Pattern"
  exit 1
}

$ageDays = [math]::Round(((Get-Date) - $newest.LastWriteTime).TotalDays, 1)
if ($ageDays -gt $MaxAgeDays) {
  $sizeGB = [math]::Round($newest.Length / 1GB, 2)
  Write-Health -EntryType 'Warning' -Message ("WSL backup stale: newest snapshot '{0}' is {1} days old ({2} GB), exceeds {3}-day threshold. Check Task Scheduler -> RevealUI-WSL-Weekly-Backup LastTaskResult." -f $newest.Name, $ageDays, $sizeGB, $MaxAgeDays)
  exit 2
}

exit 0
