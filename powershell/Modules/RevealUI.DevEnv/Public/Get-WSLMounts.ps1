function Get-WSLMounts {
    Write-Host "=== WSL Mounted Drives ===" -ForegroundColor Cyan
    wsl.exe -d Ubuntu -e bash -c "mount | grep -E 'wsl|/dev/sd' | grep -v snap"
}
