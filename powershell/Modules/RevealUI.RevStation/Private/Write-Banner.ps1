#Requires -Version 7.0
#Requires -PSEdition Core

function Write-Banner {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Banner is Windows-only: it queries wsl.exe and Windows-specific drive
    # letters. On non-Windows (e.g. CI's ubuntu-latest pwsh runners where
    # the module is imported for test purposes), skip cleanly.
    if (-not $IsWindows) { return }

    # Suppress the banner whenever stdout is redirected or the session is
    # non-interactive. Write-Host output leaks into a captured stdout pipe,
    # and a stray banner corrupts stdio JSON-RPC protocols launched through
    # PowerShell (ACP agents, MCP servers, LSP). Surfaced 2026-06-13: Zed's
    # claude-acp agent is spawned via PowerShell, read this banner as
    # JSON-RPC, and dropped the channel ("response channel cancelled").
    if ([Console]::IsOutputRedirected -or -not [Environment]::UserInteractive) { return }

    # Detect environment
    $wslDistro = (wsl --list --quiet 2>$null | Select-Object -First 1) -replace '\x00',''
    $eDrive = if (Test-Path "E:\") { "E: mounted" } else { "E: disconnected" }
    $eDriveColor = if (Test-Path "E:\") { "Green" } else { "Yellow" }

    Write-Host "`nRevealUI Workbench " -ForegroundColor Green -NoNewline
    Write-Host "(preview)" -ForegroundColor DarkGray
    Write-Host "WSL: " -NoNewline
    Write-Host "$wslDistro" -ForegroundColor Cyan -NoNewline
    Write-Host " · " -NoNewline
    Write-Host "$eDrive" -ForegroundColor $eDriveColor
    Write-Host 'Commands: ' -NoNewline
    Write-Host 'wsls' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslr' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslstat' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslmount' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslsync' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'secret' -ForegroundColor Yellow -NoNewline
    Write-Host ' | ' -NoNewline
    Write-Host 'wslhelp' -ForegroundColor Yellow
    Write-Host ""
}
