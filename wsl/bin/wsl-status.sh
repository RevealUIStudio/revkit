#!/bin/bash
# Forge environment status — called by Get-WSLStatus from PowerShell
echo "Tier: ${DEVKIT_TIER:-unknown}"
echo "Root: ${REVEALUI_ROOT:-not set}"

if mountpoint -q /mnt/forge 2>/dev/null; then
    echo "Forge: mounted"
    df -h /mnt/forge | tail -1
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^forge-' || true)
        echo "Services: $running forge container(s) running"
    else
        echo "Services: Docker not running"
    fi
else
    echo "Forge: not mounted"
fi
