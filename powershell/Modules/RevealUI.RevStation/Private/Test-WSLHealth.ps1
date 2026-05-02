#Requires -Version 7.0
#Requires -PSEdition Core

function Test-WSLHealth {
    <#
    .SYNOPSIS
        Lightweight WSL liveness probe with timeout.
    .DESCRIPTION
        Runs 'wsl.exe -d <Distribution> -e echo HEALTHCHECK' via System.Diagnostics.Process
        with a configurable timeout. Returns a structured result indicating health status.
        Uses Process API (not Start-Process) for precise timeout control — critical because
        the zombie VM state causes wsl.exe to hang indefinitely.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Distribution = 'Ubuntu',
        [int]$TimeoutSeconds = 10
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $wslPath = (Get-Command wsl.exe -ErrorAction SilentlyContinue)?.Source
    if (-not $wslPath) {
        $sw.Stop()
        return [PSCustomObject]@{
            Healthy    = $false
            Error      = 'wsl_not_found'
            Detail     = 'wsl.exe not found in PATH'
            DurationMs = $sw.ElapsedMilliseconds
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $wslPath
    $psi.Arguments = "-d $Distribution -e echo HEALTHCHECK"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)

        # Read stdout/stderr asynchronously to avoid deadlocks
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $exited = $proc.WaitForExit($TimeoutSeconds * 1000)

        if (-not $exited) {
            try { $proc.Kill() } catch { }
            $sw.Stop()
            return [PSCustomObject]@{
                Healthy    = $false
                Error      = 'timeout'
                Detail     = "wsl.exe did not respond within ${TimeoutSeconds}s"
                DurationMs = $sw.ElapsedMilliseconds
            }
        }

        # Wait for async reads to complete after process exit
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $sw.Stop()

        if ($proc.ExitCode -eq 0 -and $stdout -match 'HEALTHCHECK') {
            return [PSCustomObject]@{
                Healthy    = $true
                Error      = $null
                Detail     = ''
                DurationMs = $sw.ElapsedMilliseconds
            }
        }

        # Process exited but with error
        $detail = if ($stderr) { $stderr.Trim() } else { "exit code $($proc.ExitCode)" }
        return [PSCustomObject]@{
            Healthy    = $false
            Error      = 'wsl_error'
            Detail     = $detail
            DurationMs = $sw.ElapsedMilliseconds
        }
    }
    catch {
        $sw.Stop()
        return [PSCustomObject]@{
            Healthy    = $false
            Error      = 'exception'
            Detail     = $_.Exception.Message
            DurationMs = $sw.ElapsedMilliseconds
        }
    }
    finally {
        if ($proc) { $proc.Dispose() }
    }
}
