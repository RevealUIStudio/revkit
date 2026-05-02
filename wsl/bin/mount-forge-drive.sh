#!/bin/bash
# mount-forge-drive.sh — Mounts the Forge infrastructure drive by filesystem label
# Called by Windows mount script after wsl --mount --bare
set -euo pipefail

MOUNT_POINT="/mnt/forge"
DRIVE_LABEL="Forge"

# Already mounted?
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "Already mounted at $MOUNT_POINT"
    exit 0
fi

mkdir -p "$MOUNT_POINT"

# --- Primary: find by filesystem label ---
EXTDEV=$(blkid -L "$DRIVE_LABEL" 2>/dev/null || true)

# --- Fallback: find first unmounted ext4 partition ---
if [ -z "$EXTDEV" ]; then
    echo "WARN: Label '$DRIVE_LABEL' not found, falling back to first unmounted ext4"
    for dev in /dev/sd[a-z]1; do
        [ -b "$dev" ] || continue
        # Skip if already mounted
        if mount | grep -q "^$dev "; then
            continue
        fi
        FSTYPE=$(blkid -s TYPE -o value "$dev" 2>/dev/null || true)
        if [ "$FSTYPE" = "ext4" ]; then
            ROOT_DEV=$(mount | grep " / " | awk '{print $1}')
            if [ "$dev" = "$ROOT_DEV" ]; then
                continue
            fi
            EXTDEV="$dev"
            break
        fi
    done
fi

if [ -z "$EXTDEV" ]; then
    echo "ERROR: No partition with label '$DRIVE_LABEL' or unmounted ext4 found" >&2
    exit 1
fi

echo "Mounting $EXTDEV (label: $DRIVE_LABEL) at $MOUNT_POINT"
mount -t ext4 -o defaults,noatime "$EXTDEV" "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
    echo "SUCCESS: Mounted at $MOUNT_POINT"
else
    echo "ERROR: Mount failed" >&2
    exit 1
fi
