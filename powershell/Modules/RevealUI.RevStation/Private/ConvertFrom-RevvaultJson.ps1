#Requires -Version 7.0
#Requires -PSEdition Core

function ConvertFrom-RevvaultJson {
    <#
    .SYNOPSIS
        Parse a `revvault get --json` payload into the secret value.
    .DESCRIPTION
        revvault emits {"path": "...", "value": "..."} on success (the value
        carries the full multi-line secret, JSON-escaped) and {"error": "..."}
        on failure. revvault's process exit code is inconsistent across error
        kinds, so the JSON shape is the authoritative success/failure signal.
        Returns the secret value on success; throws a descriptive error on an
        error payload, empty output, or unparseable / unexpected JSON.
    .PARAMETER Json
        The raw stdout captured from `revvault get --json <path>`.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw 'revvault returned no output.'
    }

    $parsed = $null
    try {
        $parsed = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $snippet = if ($Json.Length -gt 200) { $Json.Substring(0, 200) } else { $Json }
        throw "revvault returned non-JSON output: $snippet"
    }

    # Strict-mode-safe membership tests (dot access to a missing property throws
    # under Set-StrictMode -Version Latest; PSObject.Properties indexing does not).
    if ($parsed.PSObject.Properties['error']) {
        throw [string]$parsed.error
    }
    if (-not $parsed.PSObject.Properties['value']) {
        throw 'revvault JSON contained neither "value" nor "error".'
    }

    return [string]$parsed.value
}
