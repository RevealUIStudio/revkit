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

## What's NOT covered (integration-only)

Functions that mutate Windows state — `Start-WSL`, `Restart-WSL`, `Mount-WSLDev`, `Get-WSLStatus`, `Get-WSLMounts`, `Register-DevMountTask`, `Unregister-DevMountTask`, `Sync-RevealUIToWindows` — require a real WSL distribution and/or Windows Task Scheduler. They are exercised manually during bootstrap and would need a Windows runner with WSL installed to test here.
