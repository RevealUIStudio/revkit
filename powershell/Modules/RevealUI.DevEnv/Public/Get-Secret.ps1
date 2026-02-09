function Get-Secret {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Distribution = "Ubuntu",

        [switch]$AsSecureString
    )

    $root = $env:REVEALUI_ROOT
    if (-not $root) {
        $root = Find-RevealUIDrive
    }
    if (-not $root) {
        Write-Error "RevealUI SSD not found. Is the drive connected?"
        return
    }

    $driveLetter = $root.Substring(0, 1).ToLower()
    $wslRoot = "/mnt/$driveLetter/.revealui"
    $passageDir = "$wslRoot/passage-store"

    $result = wsl.exe -d $Distribution -- bash -lc "PASSAGE_DIR='$passageDir' passage show '$Path'" 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "passage show failed for '$Path': $result"
        return
    }

    $secret = ($result -join "`n").Trim()

    if ($AsSecureString) {
        return ($secret | ConvertTo-SecureString -AsPlainText -Force)
    }

    return $secret
}
