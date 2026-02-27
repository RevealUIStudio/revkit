#Requires -Version 7.0
#Requires -PSEdition Core

function Find-RevealUIDrive {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$UpdateEnv
    )

    $marker = "powershell\Modules\RevealUI.DevEnv\RevealUI.DevEnv.psd1"

    # Layer 1: Check existing env var
    if ($env:REVEALUI_ROOT -and (Test-Path (Join-Path $env:REVEALUI_ROOT $marker) -ErrorAction SilentlyContinue)) {
        return $env:REVEALUI_ROOT
    }

    # Layer 2: Check user home (C: drive, always available)
    $homeRoot = Join-Path $env:USERPROFILE ".revealui"
    if (Test-Path (Join-Path $homeRoot $marker) -ErrorAction SilentlyContinue) {
        if ($UpdateEnv) {
            $env:REVEALUI_ROOT = $homeRoot
            [System.Environment]::SetEnvironmentVariable('REVEALUI_ROOT', $homeRoot, 'User')
            Write-Verbose "Updated REVEALUI_ROOT to: $homeRoot"
        }
        return $homeRoot
    }

    # Layer 3: Scan available drives for .revealui folder with our marker (portable SSD fallback)
    $found = Get-Volume | Where-Object { $_.DriveLetter } |
             ForEach-Object { "$($_.DriveLetter):\.revealui"; "$($_.DriveLetter):\professional\.revealui" } |
             Where-Object { Test-Path (Join-Path $_ $marker) -ErrorAction SilentlyContinue } |
             Select-Object -First 1

    if ($found -and $UpdateEnv) {
        $env:REVEALUI_ROOT = $found
        [System.Environment]::SetEnvironmentVariable('REVEALUI_ROOT', $found, 'User')
        Write-Verbose "Updated REVEALUI_ROOT to: $found"
    }

    return $found
}
