#!/bin/bash
# Dev drive status — called by Get-WSLStatus (wslstat) from PowerShell
if mountpoint -q /mnt/wsl-dev 2>/dev/null; then
    df -h /mnt/wsl-dev
else
    echo "Not mounted"
fi
