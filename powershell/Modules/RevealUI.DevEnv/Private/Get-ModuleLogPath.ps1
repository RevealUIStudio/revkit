#Requires -Version 7.0
#Requires -PSEdition Core

function Get-ModuleLogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $logDir = Join-Path $PSScriptRoot '..' 'logs'
    $logDir = [System.IO.Path]::GetFullPath($logDir)

    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    return $logDir
}
