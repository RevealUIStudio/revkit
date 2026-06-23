#Requires -Version 7.0
#Requires -PSEdition Core

function Get-Secret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Distribution = 'Ubuntu',

        [switch]$AsPlainText,

        [switch]$AsSecureString
    )

    if (-not $AsPlainText -and -not $AsSecureString) {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                'Specify -AsPlainText or -AsSecureString. Plaintext secrets may be logged or captured.'),
            'OutputModeRequired',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # Defence in depth: a passage entry name is a store-relative path, so a
    # newline or other control character is never legitimate and could only
    # come from a malformed or hostile caller. Reject it up front with a clear
    # error. The out-of-band env-var hand-off below already makes any value
    # non-injectable; this just fails fast rather than querying an impossible
    # key. Single quotes / semicolons / backticks are intentionally allowed
    # through (they are inert via the env-var hand-off) so legitimate exotic
    # entry names are not blocked.
    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path.IndexOfAny([char[]]@("`0", "`r", "`n")) -ge 0) {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Invalid secret path: must be a non-empty, single-line value.'),
            'InvalidPath', [System.Management.Automation.ErrorCategory]::InvalidArgument, $Path)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    $root = $env:REVEALUI_ROOT
    if (-not $root) {
        $root = Find-RevealUIDrive
    }
    if (-not $root) {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('RevealUI SSD not found. Is the drive connected?'),
            'DriveNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    # Map the full Windows root to its WSL mount. Deriving the mount from the
    # drive letter alone dropped every intermediate segment, so a root such as
    # 'D:\professional\.revealui' (a value Find-RevealUIDrive can return)
    # resolved to the wrong store. ConvertTo-WslPath preserves the whole path.
    $wslRoot = ConvertTo-WslPath $root
    $passageDir = "$wslRoot/passage-store"

    # Hand the store directory and the secret path to bash out-of-band through
    # the environment (WSLENV forwards named vars into the WSL process) instead
    # of interpolating them into the command string. The values arrive as
    # opaque environment variables, so quotes, semicolons, backticks, or
    # $(...) in either value cannot break out of the quoting and execute as
    # commands. This is the structural fix for the prior
    # `bash -lc "... passage show '$Path'"` injection.
    $previous = @{
        RV_PASSAGE_DIR = $env:RV_PASSAGE_DIR
        RV_PATH        = $env:RV_PATH
        WSLENV         = $env:WSLENV
    }
    try {
        $env:RV_PASSAGE_DIR = $passageDir
        $env:RV_PATH = $Path
        # Forward both as plain strings: no '/p' path translation. RV_PASSAGE_DIR
        # is already a WSL path and RV_PATH is an opaque store key; letting
        # wsl.exe rewrite either as a Windows path would corrupt it.
        $forward = 'RV_PASSAGE_DIR:RV_PATH'
        $env:WSLENV = if ([string]::IsNullOrEmpty($previous.WSLENV)) {
            $forward
        } else {
            "$($previous.WSLENV):$forward"
        }

        $result = wsl.exe -d $Distribution -- bash -lc 'PASSAGE_DIR="$RV_PASSAGE_DIR" passage show "$RV_PATH"' 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        # Restore the prior process environment exactly: remove vars that were
        # unset before, otherwise set them back to their previous value.
        foreach ($name in 'RV_PASSAGE_DIR', 'RV_PATH', 'WSLENV') {
            $prev = $previous[$name]
            if ($null -eq $prev) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "Env:$name" -Value $prev
            }
        }
    }

    if ($exitCode -ne 0) {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("passage show failed for '$Path': $result"),
            'PassageFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $Path)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    $secret = ($result -join "`n").Trim()

    if ($AsSecureString) {
        return ($secret | ConvertTo-SecureString -AsPlainText -Force)
    }

    return $secret
}
