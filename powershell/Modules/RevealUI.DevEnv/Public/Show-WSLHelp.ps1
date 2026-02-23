#Requires -Version 7.0
#Requires -PSEdition Core

function Show-WSLHelp {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Resolve docs path relative to module root (works regardless of drive letter)
    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $docsPath = Join-Path $moduleRoot 'docs' 'WSL-QuickReference.md'

    # Fallback: try REVEALUI_ROOT
    if (-not (Test-Path $docsPath)) {
        if ($env:REVEALUI_ROOT) {
            $docsPath = Join-Path $env:REVEALUI_ROOT 'docs' 'WSL-QuickReference.md'
        }
    }

    if (Test-Path $docsPath) {
        notepad.exe $docsPath
    } else {
        Write-Host 'Quick reference not found. Is the RevealUI SSD connected?' -ForegroundColor Yellow
        Write-Verbose "Searched: $docsPath"
    }
}
