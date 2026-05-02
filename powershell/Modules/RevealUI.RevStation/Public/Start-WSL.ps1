#Requires -Version 7.0
#Requires -PSEdition Core

function Start-WSL {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string]$Distribution = 'Ubuntu',
        [switch]$NoFilter
    )

    if ($NoFilter) {
        wsl -d $Distribution
    } else {
        wsl -d $Distribution 2>&1 | Where-Object {
            $_ -notmatch 'Failed to start the systemd user session'
        }
    }
}
