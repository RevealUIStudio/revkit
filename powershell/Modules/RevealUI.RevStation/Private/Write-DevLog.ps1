#Requires -Version 7.0
#Requires -PSEdition Core

function Write-DevLog {
    <#
    .SYNOPSIS
        Structured logging to file and console.
    .DESCRIPTION
        Writes timestamped, leveled log entries to a file and optionally to the console.
        Log files are auto-rotated when they exceed MaxSizeMB.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Source,

        [string]$LogFile,

        [int]$MaxSizeMB = 10,

        [switch]$Quiet
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] [$Source] $Message"

    # Write to log file if specified
    if ($LogFile) {
        # Auto-rotate if oversized
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length / 1MB -gt $MaxSizeMB)) {
            $archiveName = [System.IO.Path]::GetFileNameWithoutExtension($LogFile)
            $archiveExt = [System.IO.Path]::GetExtension($LogFile)
            $archivePath = Join-Path (Split-Path $LogFile) "$archiveName-$(Get-Date -Format 'yyyyMMdd-HHmmss')$archiveExt"
            Move-Item $LogFile $archivePath -Force
        }

        Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    }

    # Write to console unless suppressed
    if (-not $Quiet) {
        $color = switch ($Level) {
            'INFO'  { 'White' }
            'WARN'  { 'Yellow' }
            'ERROR' { 'Red' }
            'DEBUG' { 'Gray' }
        }
        Write-Host $Message -ForegroundColor $color
    }
}
