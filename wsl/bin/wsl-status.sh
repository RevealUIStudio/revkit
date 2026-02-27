#!/bin/bash
# Studio drive status — called by Get-WSLStatus (wslstat) from PowerShell
if mountpoint -q /mnt/studio 2>/dev/null; then
    df -h /mnt/studio
else
    echo "Not mounted"
fi
