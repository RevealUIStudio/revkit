#!/bin/bash
# Studio environment status — called by Get-WSLStatus from PowerShell
# Usage: wsl-status.sh [--json]

JSON_MODE=0
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=1 ;;
        *) echo "Usage: wsl-status.sh [--json]" >&2; exit 1 ;;
    esac
done

tier="${DEVKIT_TIER:-unknown}"
root="${REVEALUI_ROOT:-not set}"

studio_mounted=false
if mountpoint -q /mnt/studio 2>/dev/null; then
    studio_mounted=true
fi

services=0
if $studio_mounted && command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    services=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^studio-' || true)
fi

if [ "$JSON_MODE" -eq 1 ]; then
    # Escape a string for safe JSON embedding
    json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\t'/\\t}"
        s="${s//$'\r'/\\r}"
        printf '%s' "$s"
    }

    tier_val="$(json_escape "$tier")"
    root_val="$(json_escape "$root")"

    json_output="{\"tier\":\"$tier_val\",\"root\":\"$root_val\",\"studio_mounted\":$studio_mounted,\"services\":$services}"
    if command -v jq &>/dev/null; then
        printf '%s' "$json_output" | jq .
    else
        printf '%s\n' "$json_output"
    fi
else
    echo "Tier: $tier"
    echo "Root: $root"

    if $studio_mounted; then
        echo "Studio: mounted"
        df -h /mnt/studio | tail -1
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            echo "Services: $services studio container(s) running"
        else
            echo "Services: Docker not running"
        fi
    else
        echo "Studio: not mounted"
    fi
fi
