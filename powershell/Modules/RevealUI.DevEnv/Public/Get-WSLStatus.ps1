function Get-WSLStatus {
    Write-Host "`n=== WSL Status ===" -ForegroundColor Cyan
    wsl.exe --list --verbose

    Write-Host "`n=== WSL Version ===" -ForegroundColor Cyan
    wsl.exe --status

    Write-Host "`n=== Dev Drive Status ===" -ForegroundColor Cyan
    wsl.exe -d Ubuntu -e /usr/local/bin/wsl-status.sh

    Write-Host "`n=== Systemd Status ===" -ForegroundColor Cyan
    wsl.exe -d Ubuntu -e systemctl --user is-system-running

    Write-Host ""
}
