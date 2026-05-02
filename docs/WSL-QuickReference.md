# WSL Development Environment - Quick Reference

## 🚀 Quick Start Commands

| Command | Description |
|---------|-------------|
| `wsls` | Start WSL (no warnings) |
| `Restart-WSL` | Shutdown and restart WSL |
| `Get-WSLStatus` | Check WSL and Sandbox drive status |
| `Mount-WSLDev` | Run the Sandbox drive mount script |
| `Get-WSLMounts` | Show all WSL mounted drives |

## 📁 File Locations

| Item | Path |
|------|------|
| Module | `C:\Users\joshu\.revealui\powershell\Modules\RevealUI.RevStation\` |
| PowerShell Profile (pwsh 7+) | `C:\Users\joshu\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` |
| WSL Config | `/etc/wsl.conf` (inside WSL) |
| Sandbox Drive Mount | `/mnt/sandbox` (inside WSL) |

## 🔧 Manual Operations

### Start WSL
```powershell
wsls                    # Clean start (no warnings)
Start-WSL -NoFilter     # See all output
wsl -d Ubuntu          # Direct start (may show warnings)
```

### Restart WSL
```powershell
Restart-WSL            # Helper function
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
Mount-WSLDev                        # Run mount script
wsl --mount \\.\PHYSICALDRIVE1 --bare  # Manual mount
wsl --unmount \\.\PHYSICALDRIVE1       # Manual unmount
```

## 🐧 Inside WSL Commands

### Check Sandbox Drive
```bash
df -h /mnt/sandbox                 # Check Sandbox drive space
ls -la /mnt/sandbox                # List Sandbox drive contents
mount | grep sandbox               # Verify mount
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
cd /mnt/sandbox       # Sandbox drive root
```

## ⚙️ Configuration Files

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

## 🔍 Troubleshooting

### WSL Won't Start
```powershell
wsl --shutdown
wsl --unregister Ubuntu  # ⚠️ DESTRUCTIVE - backup first!
```

### Sandbox Drive Not Mounted
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

## 💡 Tips

- **Scheduled Task**: `WSL-Mount-DevDrive` runs Mount-WSLDev at logon, USB insertion, and every 30min
- **Profile Functions**: Loaded automatically in every PowerShell session
- **Sandbox Drive**: 916GB ext4 drive optimized for development
- **Systemd Warning**: False positive - systemd starts successfully after ~3 seconds
- **PowerShell Profile**: Reload with `. $PROFILE` after editing

## 🆘 Support

- WSL Issues: `wsl --help`
- PowerShell Profile: `Get-Help about_Profiles`
- This Reference: `wslhelp` or `Show-WSLHelp`

---
*Last Updated: 2026-02-27*
