# RevealUI.DevEnv - Portable development environment module

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
Set-Alias -Name wslmount  -Value Mount-WSLDev
Set-Alias -Name wslmounts -Value Get-WSLMounts
Set-Alias -Name wslhelp   -Value Show-WSLHelp

Export-ModuleMember -Function $Public.BaseName
Export-ModuleMember -Alias wsls, wslr, wslstat, wslmount, wslmounts, wslhelp

# Startup banner
Write-Banner
