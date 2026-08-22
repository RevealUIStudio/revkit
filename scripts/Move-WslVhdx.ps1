# Move-WslVhdx.ps1
# Relocates the Ubuntu WSL2 VHD from C:\WSL\<distro> to E:\WSL\<distro>
# using `wsl --manage --move` (updates the distro path; does not export/import).
# Run elevated. Shuts WSL down. A 200 GB move across volumes takes a while.

#Requires -Version 7.0

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [string]$Destination = 'E:\WSL\Ubuntu',
  [string]$LogPath = 'E:\backups\wsl-snapshots\current\move-vhdx.log'
)

$ErrorActionPreference = 'Stop'
$fallbackLog = Join-Path $env:TEMP 'move-vhdx.log'

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

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-MoveLog 'Not elevated; re-launching with UAC'
  Start-Process -FilePath 'pwsh.exe' -Verb RunAs -Wait -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
  )
  exit $LASTEXITCODE
}

$src = "C:\WSL\$Distro\ext4.vhdx"
if (-not (Test-Path -LiteralPath $src)) {
  $already = Join-Path $Destination 'ext4.vhdx'
  if (Test-Path -LiteralPath $already) {
    Write-MoveLog "VHD already at $already; nothing to move"
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
Write-MoveLog 'Shutting down WSL (all distros stop here)'
& wsl.exe --shutdown
Start-Sleep -Seconds 8

if (-not (Test-Path -LiteralPath $Destination)) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

Write-MoveLog "wsl --manage $Distro --move $Destination"
& wsl.exe --manage $Distro --move $Destination
if ($LASTEXITCODE -ne 0) {
  throw "wsl --manage --move failed with exit $LASTEXITCODE"
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
