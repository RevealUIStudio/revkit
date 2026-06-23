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

    # Defence in depth: a vault entry name is a store-relative path, so a
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
    $storeDir = "$wslRoot/passage-store"

    # Hand the store directory and the secret path to bash out-of-band through
    # the environment (WSLENV forwards named vars into the WSL process) instead
    # of interpolating them into the command string. The values arrive as
    # opaque environment variables, so quotes, semicolons, backticks, or
    # $(...) in either value cannot break out of the quoting and execute as
    # commands. (This is the structural fix for the original
    # `bash -lc "... show '$Path'"` command injection.)
    #
    # revvault is the canonical secret backend (see revkit
    # shell/shellrc.d/40-secrets.sh). `--json` is used deliberately: it returns
    # {"value": "..."} on success with the FULL multi-line secret (JSON-escaped)
    # and {"error": "..."} on failure, which is a reliable success/failure
    # signal. Plain `revvault get` would instead truncate to the first line and
    # has inconsistent exit codes across error kinds.
    $previous = @{
        RV_STORE = $env:RV_STORE
        RV_PATH  = $env:RV_PATH
        WSLENV   = $env:WSLENV
    }
    try {
        $env:RV_STORE = $storeDir
        $env:RV_PATH = $Path
        # Forward both as plain strings: no '/p' path translation. RV_STORE is
        # already a WSL path and RV_PATH is an opaque store key; letting wsl.exe
        # rewrite either as a Windows path would corrupt it.
        $forward = 'RV_STORE:RV_PATH'
        $env:WSLENV = if ([string]::IsNullOrEmpty($previous.WSLENV)) {
            $forward
        } else {
            "$($previous.WSLENV):$forward"
        }

        $raw = wsl.exe -d $Distribution -- bash -lc 'REVVAULT_STORE="$RV_STORE" revvault get --json "$RV_PATH"' 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        # Restore the prior process environment exactly: remove vars that were
        # unset before, otherwise set them back to their previous value.
        foreach ($name in 'RV_STORE', 'RV_PATH', 'WSLENV') {
            $prev = $previous[$name]
            if ($null -eq $prev) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "Env:$name" -Value $prev
            }
        }
    }

    try {
        $secret = ConvertFrom-RevvaultJson (($raw -join "`n").Trim())
    } catch {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("revvault get failed for '$Path' (exit $exitCode): $($_.Exception.Message)"),
            'RevvaultFailed', [System.Management.Automation.ErrorCategory]::InvalidResult, $Path)
        $PSCmdlet.ThrowTerminatingError($err)
    }

    if ($AsSecureString) {
        return ($secret | ConvertTo-SecureString -AsPlainText -Force)
    }

    return $secret
}
