#Requires -Version 7.0
#Requires -PSEdition Core

function ConvertTo-WslPath {
    <#
    .SYNOPSIS
        Convert a Windows drive-letter path to its WSL drvfs mount equivalent.
    .DESCRIPTION
        Maps 'D:\professional\.revealui' to '/mnt/d/professional/.revealui'.
        Every path segment is preserved; deriving the mount from the drive
        letter alone would drop intermediate directories (for example the
        'professional' root that Find-RevealUIDrive can return for a
        '<drive>:\professional\.revealui' layout).
    .PARAMETER WindowsPath
        An absolute Windows drive-letter path (e.g. 'D:\dir\sub').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$WindowsPath
    )

    if ($WindowsPath.Length -lt 2 -or $WindowsPath.Substring(1, 1) -ne ':') {
        throw "ConvertTo-WslPath: expected a drive-letter path (e.g. 'D:\dir'), got '$WindowsPath'."
    }

    $driveLetter = $WindowsPath.Substring(0, 1).ToLowerInvariant()
    $rest = $WindowsPath.Substring(2).Replace('\', '/')
    if (-not $rest.StartsWith('/')) {
        $rest = "/$rest"
    }

    return ("/mnt/$driveLetter$rest").TrimEnd('/')
}
