function Start-WSL {
    param(
        [string]$Distribution = "Ubuntu",
        [switch]$NoFilter
    )

    if ($NoFilter) {
        wsl -d $Distribution
    } else {
        wsl -d $Distribution 2>&1 | Where-Object {
            $_ -notmatch "Failed to start the systemd user session"
        }
    }
}
