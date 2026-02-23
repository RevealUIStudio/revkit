#Requires -Version 7.0
#Requires -PSEdition Core

function Get-Secret {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Distribution = 'Ubuntu',

        [switch]$AsSecureString
    )

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

    if (-not $AsSecureString) {
        Write-Warning 'Secret will be returned as plaintext. Use -AsSecureString for sensitive contexts.'
    }

    $driveLetter = $root.Substring(0, 1).ToLower()
    $wslRoot = "/mnt/$driveLetter/.revealui"
    $passageDir = "$wslRoot/passage-store"

    $result = wsl.exe -d $Distribution -- bash -lc "PASSAGE_DIR='$passageDir' passage show '$Path'" 2>&1

    if ($LASTEXITCODE -ne 0) {
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
