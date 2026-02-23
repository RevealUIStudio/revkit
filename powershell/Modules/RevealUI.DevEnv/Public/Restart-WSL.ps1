#Requires -Version 7.0
#Requires -PSEdition Core

function Restart-WSL {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [string]$Distribution = 'Ubuntu'
    )

    if (-not $PSCmdlet.ShouldProcess('WSL', 'Shutdown and restart')) {
        return
    }

    Write-Host 'Shutting down WSL...' -ForegroundColor Yellow
    wsl --shutdown

    Write-Host 'Waiting for shutdown...' -ForegroundColor Yellow
    Start-Sleep -Seconds 3

    Write-Host 'Mounting dev drive...' -ForegroundColor Yellow
    Mount-WSLDev

    Write-Host 'Initializing WSL...' -ForegroundColor Green
    wsl.exe -d $Distribution -e true 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    Write-Host "`nWSL restart complete!" -ForegroundColor Green
    Write-Host 'Use ' -NoNewline
    Write-Host 'wsls' -ForegroundColor Cyan -NoNewline
    Write-Host ' to connect or ' -NoNewline
    Write-Host 'wslstat' -ForegroundColor Cyan -NoNewline
    Write-Host ' to check status' -NoNewline
    Write-Host ''
}
