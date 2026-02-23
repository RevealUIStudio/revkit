#Requires -Version 7.0
#Requires -PSEdition Core

function Sync-RevealUIToWindows {
    <#
    .SYNOPSIS
        Mirrors RevealUI from WSL to Windows for read-only access by Windows apps.
    .DESCRIPTION
        Uses robocopy to mirror the RevealUI monorepo from WSL Ubuntu ext4 to a
        Windows NTFS path. Excludes build artifacts, node_modules, and other
        non-essential directories. Supports dry-run mode and structured logging.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [switch]$DryRun,

        [ValidateSet('manual', 'scheduled', 'startup')]
        [string]$TriggerSource = 'manual',

        [string]$WslDistro = 'Ubuntu',

        [string]$Source = '\\wsl.localhost\Ubuntu\home\joshua-v-dev\projects\RevealUI',

        [string]$Destination = 'C:\Users\joshu\projects\RevealUI'
    )

    $logDir = Get-ModuleLogPath
    $logFile = Join-Path $logDir 'sync-revealui.log'

    $ExcludeDirs = @(
        'node_modules', '.next', 'dist', '.turbo', '.git', '.pgdata',
        '.nix-store', '.direnv', '.claude', '.husky', 'coverage',
        '.vitest', '.playwright'
    )

    $ExcludeFiles = @(
        'pnpm-lock.yaml', '*.lock'
    )

    Write-DevLog "Starting RevealUI sync ($TriggerSource)" -Source 'Sync' -LogFile $logFile

    # Check WSL availability
    $wslCheck = wsl.exe -d $WslDistro -e echo READY 2>&1
    if ($wslCheck -notmatch 'READY') {
        Write-DevLog 'WSL not available. Skipping sync.' -Level WARN -Source 'Sync' -LogFile $logFile
        return
    }

    if (-not (Test-Path $Source)) {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.IO.DirectoryNotFoundException]::new("Source not found: $Source"),
            'SourceNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Source)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    $destParent = Split-Path $Destination -Parent
    if (-not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }

    $robocopyArgs = @(
        $Source, $Destination
        '/MIR', '/COPY:DT', '/DCOPY:T', '/MT:8'
        '/R:2', '/W:3', '/NP', '/NDL', '/NFL', '/NJH', '/NJS'
        "/LOG+:$logFile"
    )

    foreach ($dir in $ExcludeDirs) {
        $robocopyArgs += '/XD'
        $robocopyArgs += $dir
    }

    foreach ($file in $ExcludeFiles) {
        $robocopyArgs += '/XF'
        $robocopyArgs += $file
    }

    if ($DryRun) {
        $robocopyArgs += '/L'
        Write-DevLog 'DRY RUN mode - no files will be copied' -Level INFO -Source 'Sync' -LogFile $logFile
    }

    if (-not $PSCmdlet.ShouldProcess("$Source -> $Destination", 'Robocopy mirror')) {
        return
    }

    $startTime = Get-Date
    Write-DevLog "Syncing: $Source -> $Destination" -Source 'Sync' -LogFile $logFile

    & robocopy @robocopyArgs

    $exitCode = $LASTEXITCODE
    $secs = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

    if ($exitCode -le 7) {
        $status = switch ($exitCode) {
            0 { 'Already in sync' }
            1 { 'Files copied' }
            2 { 'Extras cleaned' }
            3 { 'Files copied + extras cleaned' }
            default { "Completed with code $exitCode" }
        }
        Write-DevLog "Sync complete: $status (${secs}s)" -Source 'Sync' -LogFile $logFile
    } else {
        Write-DevLog "Sync FAILED with exit code $exitCode (${secs}s)" -Level ERROR -Source 'Sync' -LogFile $logFile
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Robocopy failed with exit code $exitCode"),
            'RobocopyFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }
}
