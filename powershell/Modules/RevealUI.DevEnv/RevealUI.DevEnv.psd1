@{
    RootModule             = 'RevealUI.DevEnv.psm1'
    ModuleVersion          = '1.0.0'
    GUID                   = 'a3f7c8e1-9b2d-4f6a-8e5c-1d3b7a9f2c4e'
    Author                 = 'RevealUI Studio'
    CompanyName            = 'RevealUI'
    Copyright              = '(c) RevealUI Studio. All rights reserved.'
    Description            = 'WSL development environment helpers for RevealUI portable dev setup'
    PowerShellVersion      = '7.0'
    CompatiblePSEditions   = @('Core')

    FunctionsToExport = @(
        'Start-WSL'
        'Restart-WSL'
        'Mount-WSLDev'
        'Get-WSLStatus'
        'Get-WSLMounts'
        'Find-RevealUIDrive'
        'Show-WSLHelp'
        'Get-Secret'
        'Sync-RevealUIToWindows'
        'Sync-AllRepos'
        'Register-DevMountTask'
        'Register-SyncTask'
        'Unregister-DevMountTask'
        'Unregister-SyncTask'
    )

    AliasesToExport   = @(
        'wsls'
        'wslr'
        'wslstat'
        'wslmount'
        'wslmounts'
        'wslhelp'
        'wslsync'
        'syncall'
        'secret'
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('WSL', 'DevEnv', 'RevealUI')
        }
    }
}
