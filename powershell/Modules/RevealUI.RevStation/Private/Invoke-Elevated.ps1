#Requires -Version 7.0
#Requires -PSEdition Core

function Invoke-Elevated {
    <#
    .SYNOPSIS
        Runs a PowerShell command in an elevated pwsh.exe process with module discovery.
    .DESCRIPTION
        Launches pwsh.exe as admin, discovers the RevealUI.RevStation module on any drive,
        imports it, and executes the supplied command string. Uses -EncodedCommand to
        avoid escaping issues with Start-Process argument passing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [switch]$Wait
    )

    # Inline module discovery + caller's command
    $script = @"
`$r = Get-Volume | Where-Object DriveLetter | ForEach-Object { "`$(`$_.DriveLetter):\.revealui"; "`$(`$_.DriveLetter):\professional\.revealui" } |
  Where-Object { Test-Path "`$_\powershell\Modules\RevealUI.RevStation" } | Select-Object -First 1
if (`$r) {
  `$env:PSModulePath = (Join-Path `$r 'powershell\Modules') + ';' + `$env:PSModulePath
  Import-Module RevealUI.RevStation
  $Command
} else { Write-Error 'RevealUI.RevStation module not found on any drive' }
"@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))

    $arguments = @(
        '-NonInteractive'
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-EncodedCommand', $encoded
    )

    $startParams = @{
        FilePath     = 'pwsh.exe'
        Verb         = 'RunAs'
        ArgumentList = $arguments
    }

    if ($Wait) {
        $startParams['Wait'] = $true
    }

    Start-Process @startParams
}
