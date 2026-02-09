function Write-Banner {
    Write-Host "`nWSL Helpers Loaded!" -ForegroundColor Green
    Write-Host "Commands: " -NoNewline
    Write-Host "wsls" -ForegroundColor Yellow -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "wslr" -ForegroundColor Yellow -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "wslstat" -ForegroundColor Yellow -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "wslmount" -ForegroundColor Yellow -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "secret" -ForegroundColor Yellow -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "wslhelp" -ForegroundColor Yellow
    Write-Host "Type " -NoNewline
    Write-Host "wslhelp" -ForegroundColor Cyan -NoNewline
    Write-Host " for full reference`n"
}
