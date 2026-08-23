# Apply-WslHostFix.ps1
# One elevated operator entry: wrap the weekly backup task (headless + WakeToRun),
# then move the Ubuntu VHD off C: onto E:.
# Shuts WSL down for the move. Confirm UAC; expect this session to die.

#Requires -Version 7.0

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [string]$Destination = 'E:\WSL\Ubuntu'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Start-Process -FilePath 'pwsh.exe' -Verb RunAs -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
    '-Distro', $Distro, '-Destination', $Destination
  )
  return
}

$register = Join-Path $here 'Register-WeeklyBackupTask.ps1'
$move = Join-Path $here 'Move-WslVhdx.ps1'
if (-not (Test-Path $register)) { throw "Missing $register" }
if (-not (Test-Path $move)) { throw "Missing $move" }

Write-Host '=== 1/2 Register-WeeklyBackupTask (conhost --headless, WakeToRun) ==='
& $register
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Register-WeeklyBackupTask failed: $LASTEXITCODE" }

Write-Host '=== 2/2 Move-WslVhdx (wsl --shutdown, then --manage --move) ==='
& $move -Distro $Distro -Destination $Destination
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Move-WslVhdx failed: $LASTEXITCODE" }

Write-Host 'Apply-WslHostFix DONE'
