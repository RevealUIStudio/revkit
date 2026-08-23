# Move-WslVhdx.ps1
# Relocates the Ubuntu WSL2 VHD from C:\WSL\<distro> to E:\WSL\<distro>
# using `wsl --manage --move` (updates the distro path; does not export/import).
# Run elevated from Windows, not from the distro being moved.
# Shuts WSL down. A 200 GB move across volumes takes a while.

#Requires -Version 7.0

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [string]$Destination = 'E:\WSL\Ubuntu',
  [string]$LogPath = $(
    if ($env:REVEALUI_WSL_SNAPSHOT_DIR) {
      Join-Path $env:REVEALUI_WSL_SNAPSHOT_DIR 'move-vhdx.log'
    } else {
      $null
    }
  )
)

$ErrorActionPreference = 'Stop'
if (-not $LogPath) {
  # Never log under $Destination: Write-MoveLog creates the parent directory,
  # which would re-create an empty dest and make `wsl --manage --move` fail.
  $LogPath = Join-Path $env:TEMP 'move-vhdx.log'
}
$fallbackLog = Join-Path $env:TEMP 'move-vhdx.log'
$mutex = $null
$heldMutex = $false

function Write-MoveLog {
  param([string]$Message)
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
  Write-Host $line
  foreach ($p in @($LogPath, $fallbackLog)) {
    try {
      $dir = Split-Path $p -Parent
      if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
      }
      Add-Content -Path $p -Value $line -ErrorAction Stop
    } catch {
      # keep going; at least one log target should work
    }
  }
}

function Unlock-MoveMutex {
  if ($heldMutex -and $mutex) {
    try { $mutex.ReleaseMutex() } catch { }
    $script:heldMutex = $false
  }
  if ($mutex) {
    try { $mutex.Dispose() } catch { }
    $script:mutex = $null
  }
}

function Wait-WslVhdReleased {
  param(
    [Parameter(Mandatory)][string]$VhdPath,
    [int]$TimeoutSeconds = 180
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $attempt = 0
  while ((Get-Date) -lt $deadline) {
    $attempt++
    Write-MoveLog "wsl --shutdown (attempt $attempt)"
    & wsl.exe --shutdown
    Start-Sleep -Seconds 5
    try {
      $fs = [System.IO.File]::Open(
        $VhdPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None)
      $fs.Dispose()
      Write-MoveLog 'VHD handle released'
      return
    } catch {
      Write-MoveLog "VHD still in use: $($_.Exception.Message)"
    }
  }
  throw "WSL VHD still in use after ${TimeoutSeconds}s: $VhdPath"
}

trap {
  Write-MoveLog "ERROR: $($_.Exception.Message)"
  Unlock-MoveMutex
  break
}

# Idempotent no-op MUST run before UAC and before any wsl --shutdown.
# 2026-08-23: the VHD is already on E:. A recover session that re-ran this
# script would have killed a live WSL if the check sat after elevation.
$src = "C:\WSL\$Distro\ext4.vhdx"
$already = Join-Path $Destination 'ext4.vhdx'
if (-not (Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $already)) {
  Write-MoveLog "VHD already at $already; nothing to move"
  exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-MoveLog 'Not elevated; re-launching with UAC'
  $launch = @{
    FilePath          = 'pwsh.exe'
    Verb              = 'RunAs'
    WorkingDirectory  = $env:TEMP
    ArgumentList      = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  }
  # Do not -Wait from inside the distro being moved: shutdown kills the waiter.
  if (-not $env:WSL_DISTRO_NAME) {
    $launch.Wait = $true
  }
  Start-Process @launch
  exit 0
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\RevealUI-Move-WslVhdx')
try {
  $got = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
  $got = $true
}
if (-not $got) {
  Write-MoveLog 'Another Move-WslVhdx is already running; exiting'
  Unlock-MoveMutex
  exit 0
}
$heldMutex = $true

if (-not (Test-Path -LiteralPath $src)) {
  if (Test-Path -LiteralPath $already) {
    Write-MoveLog "VHD already at $already; nothing to move"
    Unlock-MoveMutex
    exit 0
  }
  throw "Source VHD not found: $src"
}

$srcSize = (Get-Item -LiteralPath $src).Length
$destRoot = Split-Path $Destination -Qualifier
if (-not $destRoot) { $destRoot = 'E:' }
$destDrive = Get-PSDrive -Name $destRoot.TrimEnd(':')
$need = [int64]($srcSize * 1.1)
if ($destDrive.Free -lt $need) {
  throw "Not enough free space on $destRoot : have $($destDrive.Free) need $need"
}

Write-MoveLog "Moving $src ($([math]::Round($srcSize/1GB,1)) GB) -> $Destination"
Wait-WslVhdReleased -VhdPath $src

# wsl --manage --move creates the destination directory. Pre-creating it
# (or leaving an empty leftover from an aborted run) makes the move fail
# immediately with the VHD still on C:. 2026-08-22: E:\WSL\Ubuntu was empty
# and move-vhdx.log stopped at the --manage line.
if (Test-Path -LiteralPath $Destination) {
  $leftover = @(Get-ChildItem -LiteralPath $Destination -Force)
  if ($leftover.Count -eq 0) {
    Write-MoveLog "Removing empty leftover $Destination"
    Remove-Item -LiteralPath $Destination -Force
  } else {
    throw "Destination exists and is not empty: $Destination"
  }
}

$manageExit = -1
$manageOut = ''
for ($try = 1; $try -le 5; $try++) {
  Write-MoveLog "wsl --manage $Distro --move $Destination (try $try/5)"
  $manageOut = & wsl.exe --manage $Distro --move $Destination 2>&1 | Out-String
  $manageExit = $LASTEXITCODE
  if ($manageOut.Trim()) { Write-MoveLog "wsl --manage output: $($manageOut.Trim())" }
  if ($manageExit -eq 0) { break }
  if ($manageOut -match 'DISTRO_NOT_STOPPED|currently in use') {
    Wait-WslVhdReleased -VhdPath $src
    continue
  }
  throw "wsl --manage --move failed with exit $manageExit"
}
if ($manageExit -ne 0) {
  throw "wsl --manage --move failed with exit $manageExit"
}

$destVhd = Join-Path $Destination 'ext4.vhdx'
if (-not (Test-Path -LiteralPath $destVhd)) {
  throw "Move reported success but $destVhd is missing"
}

Write-MoveLog "VHD now at $destVhd ($([math]::Round((Get-Item $destVhd).Length/1GB,1)) GB)"
if (Test-Path -LiteralPath $src) {
  Write-MoveLog "WARN source still present: $src"
} else {
  Write-MoveLog "Source removed: $src"
}
Write-MoveLog 'DONE'
Unlock-MoveMutex
