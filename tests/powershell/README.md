# PowerShell tests — RevealUI.RevStation

Cross-platform Pester v5 tests for the PowerShell module.

## Run locally

```pwsh
# One-time install (any host OS with PowerShell 7+)
Install-Module -Name Pester -RequiredVersion 5.5.0 -Force -SkipPublisherCheck

# From the repo root
Invoke-Pester ./tests/powershell/
```

## What's covered

| File | Function(s) | Notes |
| --- | --- | --- |
| `Module.Tests.ps1` | Manifest + exports | `Test-ModuleManifest`; 11 public functions + 8 aliases enumerated |
| `Find-RevealUIDrive.Tests.ps1` | `Find-RevealUIDrive` | Layer 1 (env var) + Layer 2 (USERPROFILE). Layer 3 (`Get-Volume`) is Windows-only, intentionally not exercised on Linux runners. |
| `Get-Secret.Tests.ps1` | `Get-Secret` | Argument-validation guards (OutputModeRequired error; mandatory `-Path`). |
| `Show-WSLHelp.Tests.ps1` | `Show-WSLHelp` | Docs file presence (`WSL-QuickReference.md`) + module export. Launch path (opens `notepad.exe`) is not exercised — unreliable to mock; lives in the manual integration suite. |
| `Register-DevMountTask.Tests.ps1` | `Register-DevMountTask` | Self-elevation `-WhatIf` / `-Confirm` contract: under `-WhatIf` the non-elevated branch must not call `Invoke-Elevated` (mocked `Test-IsAdmin` / `Invoke-Elevated`). The scheduled-task registration path stays integration-only. |
| `Unregister-DevMountTask.Tests.ps1` | `Unregister-DevMountTask` | Same self-elevation `-WhatIf` contract as `Register-DevMountTask` (`ConfirmImpact = High`). The scheduled-task removal path stays integration-only. |
| `WslHostScripts.Tests.ps1` | Register-WeeklyBackupTask / Move-WslVhdx / Apply-WslHostFix / Register-VHDxCompactTask | Source contracts: conhost `--headless`, WakeToRun, `wsl --manage --move` to `E:\WSL`, no export/import, do not pre-create the move destination. Task Scheduler writes stay integration-only. |

## What's NOT covered (integration-only)

Functions that mutate Windows state (`Start-WSL`, `Restart-WSL`, `Mount-WSLDev`, `Get-WSLStatus`, `Get-WSLMounts`, `Sync-RevealUIToWindows`) require a real WSL distribution and/or Windows Task Scheduler. They are exercised manually during bootstrap and would need a Windows runner with WSL installed to test here. For `Register-DevMountTask` and `Unregister-DevMountTask`, the self-elevation `-WhatIf` contract is unit-tested above (mocked `Test-IsAdmin` / `Invoke-Elevated`); only the Task Scheduler registration and removal itself remains integration-only.
