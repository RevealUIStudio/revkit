#Requires -Version 7.0
#Requires -PSEdition Core

# RevealUI.RevStation - Workstation orchestration module

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Public  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)

foreach ($import in @($Public + $Private)) {
    try {
        . $import.FullName
    } catch {
        Write-Error "Failed to import $($import.FullName): $_"
    }
}

# Aliases
Set-Alias -Name wsls      -Value Start-WSL
Set-Alias -Name wslr      -Value Restart-WSL
Set-Alias -Name wslstat   -Value Get-WSLStatus
Set-Alias -Name wslmount   -Value Mount-WSLDev
Set-Alias -Name wslunmount -Value Dismount-WSLDev
Set-Alias -Name wslmounts  -Value Get-WSLMounts
Set-Alias -Name wslhelp   -Value Show-WSLHelp
Set-Alias -Name wslsync   -Value Sync-RevealUIToWindows
Set-Alias -Name secret    -Value Get-Secret
Set-Alias -Name wslhealth -Value Invoke-WSLRecovery

Export-ModuleMember -Function $Public.BaseName
Export-ModuleMember -Alias wsls, wslr, wslstat, wslmount, wslunmount, wslmounts, wslhelp, wslsync, secret, wslhealth

# Startup banner
Write-Banner
