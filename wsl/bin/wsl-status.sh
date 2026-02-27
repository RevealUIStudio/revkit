#!/bin/bash
# Studio environment status — called by Get-WSLStatus from PowerShell
echo "Tier: ${DEVKIT_TIER:-unknown}"
echo "Root: ${REVEALUI_ROOT:-not set}"

if mountpoint -q /mnt/studio 2>/dev/null; then
    echo "Studio: mounted"
    df -h /mnt/studio | tail -1
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^studio-' || true)
        echo "Services: $running studio container(s) running"
    else
        echo "Services: Docker not running"
    fi
else
    echo "Studio: not mounted"
fi
