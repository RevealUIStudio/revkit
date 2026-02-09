function Show-WSLHelp {
    $docsPath = if ($env:REVEALUI_ROOT) {
        Join-Path $env:REVEALUI_ROOT "docs\WSL-QuickReference.md"
    } else {
        $null
    }

    # Fallback to legacy location
    if (-not $docsPath -or -not (Test-Path $docsPath)) {
        $docsPath = "C:\Scripts\WSL-QuickReference.md"
    }

    if (Test-Path $docsPath) {
        notepad.exe $docsPath
    } else {
        Write-Host "Quick reference not found. Is the RevealUI SSD connected?" -ForegroundColor Yellow
    }
}
