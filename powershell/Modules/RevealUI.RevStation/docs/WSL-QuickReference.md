# WSL Development Environment - Quick Reference

## Quick Start Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `Start-WSL` | `wsls` | Start WSL (filtered output) |
| `Restart-WSL` | `wslr` | Shutdown and restart WSL |
| `Get-WSLStatus` | `wslstat` | Check WSL and Forge drive status |
| `Mount-WSLDev` | `wslmount` | Mount Forge SSD to WSL |
| `Dismount-WSLDev` | `wslunmount` | Safely eject Forge SSD from WSL |
| `Get-WSLMounts` | `wslmounts` | Show all WSL mounted drives |
| `Sync-RevealUIToWindows` | `wslsync` | Mirror WSL project to Windows |
| `Get-Secret` | `secret` | Retrieve secrets via passage |
| `Show-WSLHelp` | `wslhelp` | Open this reference |

## Task Scheduler Commands (elevated)

| Command | Description |
|---------|-------------|
| `Register-DevMountTask` | Register auto-mount scheduled task |
| `Unregister-DevMountTask` | Remove auto-mount scheduled task |
| `Register-SyncTask` | Register WSL-to-Windows sync task |
| `Unregister-SyncTask` | Remove sync scheduled task |

## File Locations

| Item | Path |
|------|------|
| Module | `C:\Users\joshu\.revealui\powershell\Modules\RevealUI.RevStation\` |
| Logs | `<module>\logs\` |
| PowerShell Profile | `~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` |
| WSL Config | `/etc/wsl.conf` (inside WSL) |
| Forge Drive Mount | `/mnt/forge` (inside WSL) |

## Manual Operations

### Start WSL
```powershell
wsls                    # Clean start (no warnings)
Start-WSL -NoFilter     # See all output
wsl -d Ubuntu          # Direct start (may show warnings)
```

### Restart WSL
```powershell
Restart-WSL            # Full restart with mount
# OR manually:
wsl --shutdown
Mount-WSLDev
wsls
```

### Check Status
```powershell
Get-WSLStatus          # Comprehensive status check
wsl --list --verbose   # WSL distributions
wsl --status           # WSL version info
```

### Mount Operations
```powershell
Mount-WSLDev                        # Auto-discover and mount
Mount-WSLDev -WhatIf               # Preview without mounting
wsl --mount \\.\PHYSICALDRIVE1 --bare  # Manual mount
wsl --unmount \\.\PHYSICALDRIVE1       # Manual unmount
```

### Sync Operations
```powershell
Sync-RevealUIToWindows              # Full sync
Sync-RevealUIToWindows -DryRun      # Preview only
wslsync                             # Alias
```

## Inside WSL Commands

### Check Forge Drive
```bash
df -h /mnt/forge                 # Check Forge drive space
ls -la /mnt/forge                # List Forge drive contents
mount | grep forge               # Verify mount
```

### Check Systemd Status
```bash
systemctl --user is-system-running # Check if running
loginctl user-status $USER         # Detailed user session info
journalctl --user -xe              # User session logs
```

### Navigate to Projects
```bash
cd ~/projects          # Your main projects directory
cd /mnt/forge       # Forge drive root
```

## Configuration Files

### WSL Config (`/etc/wsl.conf`)
```ini
[boot]
  systemd=true
  systemdTimeout=30

[automount]
  enabled = true
  root = /mnt/
  options = "metadata,umask=22,fmask=11"
  mountFsTab = true

[user]
  default=joshua-v-dev
```

## Troubleshooting

### WSL Won't Start
```powershell
wsl --shutdown
wsl --unregister Ubuntu  # DESTRUCTIVE - backup first!
```

### Forge Drive Not Mounted
```powershell
wsl --unmount \\.\PHYSICALDRIVE1
Mount-WSLDev
```

### Systemd Issues (inside WSL)
```bash
systemctl --user status
journalctl --user -b
loginctl user-status $USER
```

### Reset Everything
```powershell
wsl --shutdown
wsl --unmount \\.\PHYSICALDRIVE1
# Wait 5 seconds
Mount-WSLDev
```

## Tips

- **Scheduled Tasks**: `Register-DevMountTask` and `Register-SyncTask` use pwsh.exe (PS7)
- **Module Loading**: Loaded automatically in every pwsh session via profile stub
- **Forge Drive**: 916GB ext4 drive optimized for development
- **Systemd Warning**: False positive - systemd starts successfully after ~3 seconds
- **PowerShell Profile**: Reload with `. $PROFILE` after editing

## Support

- WSL Issues: `wsl --help`
- Module commands: `Get-Command -Module RevealUI.RevStation`
- This Reference: `Show-WSLHelp` or `wslhelp`

---
*Last Updated: 2026-02-27*
