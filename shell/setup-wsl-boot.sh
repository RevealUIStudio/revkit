#!/bin/bash
# RevealUI WSL Boot Optimization
# Idempotent — safe to re-run after config changes.
#
# Usage (from WSL):
#   sudo bash /mnt/e/professional/.revealui/shell/setup-wsl-boot.sh
#   sudo bash /mnt/e/professional/.revealui/shell/setup-wsl-boot.sh --revert
#
# After running, restart WSL from Windows:
#   wsl --shutdown

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# Deploy a config file (stripping CRLF) without ever truncating the destination
# on a missing or unreadable source. A naive `sed ... > "$dest"` truncates $dest
# BEFORE sed runs, so a missing source leaves a 0-byte boot-critical file and,
# under `set -euo pipefail`, aborts the run. Guard the source, render to a temp
# file, then replace the destination atomically with mv only on success.
deploy_config() {
    local src="$1" dest="$2" tmp
    if [ ! -f "$src" ]; then
        echo "ERROR: missing config source: $src" >&2
        echo "       Refusing to deploy; left $dest unchanged." >&2
        exit 1
    fi
    tmp="$(mktemp)"
    if sed 's/\r$//' "$src" > "$tmp"; then
        chmod 0644 "$tmp"
        mv "$tmp" "$dest"
    else
        rm -f "$tmp"
        echo "ERROR: failed to render config source: $src" >&2
        exit 1
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)." >&2
    exit 1
fi

# Shared service lists (used by both apply and revert)
MASK_SERVICES=(
    plymouth-quit-wait.service
    plymouth-quit.service
    plymouth-start.service
    plymouth-read-write.service
    blk-availability.service
    open-iscsi.service
    iscsid.service
    iscsid.socket
    landscape-client.service
    ModemManager.service
    multipathd.service
    multipathd.socket
    fwupd.service
    udisks2.service
    accounts-daemon.service
    power-profiles-daemon.service
    switcheroo-control.service
    thermald.service
    NetworkManager-wait-online.service
    snap.lxd.activate.service
    snap.lxd.daemon.service
    wsl-pro.service
    systemd-remount-fs.service
)

# docker.service + containerd.service are disabled at boot, but their *.socket
# units are intentionally NOT listed here: they stay enabled so the first
# `docker` call is socket-activated on demand (no sudo start needed). This is
# what sandbox-services.sh:ensure_docker() relies on.
DISABLE_SERVICES=(
    docker.service
    containerd.service
    snapd.service
    snapd.seeded.service
    snapd.autoimport.service
)

# Detect Windows home — prefer $WINDOWS_HOME env override, then user with .revealui/, else first non-system /mnt/c/Users/* dir
if [ -z "${WINDOWS_HOME:-}" ]; then
    for _hd in /mnt/c/Users/*/.revealui; do
        [ -d "$_hd" ] || continue
        WINDOWS_HOME="$(dirname "$_hd")"
        break
    done
fi
if [ -z "${WINDOWS_HOME:-}" ]; then
    for _hd in /mnt/c/Users/*/; do
        _name="$(basename "$_hd")"
        case "$_name" in
            Public|Default*|"All Users"|"") continue ;;
        esac
        WINDOWS_HOME="${_hd%/}"
        break
    done
fi
if [ -z "${WINDOWS_HOME:-}" ] || [ ! -d "$WINDOWS_HOME" ]; then
    echo "ERROR: Could not detect Windows user home in /mnt/c/Users/" >&2
    echo "       Set WINDOWS_HOME explicitly (e.g. WINDOWS_HOME=/mnt/c/Users/<your-user>)." >&2
    exit 1
fi

# ============================================================
# --revert: undo all boot optimizations
# ============================================================
if [ "${1:-}" = "--revert" ]; then
    echo ""
    echo "=== Reverting WSL Boot Optimizations ==="
    echo ""

    # --- Step 1: Unmask services ---
    echo "[1/5] Unmasking services..."
    for svc in "${MASK_SERVICES[@]}"; do
        systemctl unmask "$svc" 2>/dev/null || true
    done
    echo "  Unmasked ${#MASK_SERVICES[@]} services"

    # --- Step 2: Re-enable disabled services ---
    echo "[2/5] Re-enabling services..."
    for svc in "${DISABLE_SERVICES[@]}"; do
        systemctl enable "$svc" 2>/dev/null || true
    done
    echo "  Re-enabled ${#DISABLE_SERVICES[@]} services"

    # --- Step 3: Restore default target ---
    echo "[3/5] Restoring default target to graphical.target..."
    systemctl set-default graphical.target > /dev/null 2>&1
    echo "  Default target: graphical.target"

    # --- Step 4: Remove .wslconfig from Windows home ---
    echo "[4/5] Removing .wslconfig from Windows home..."
    if [ -f "$WINDOWS_HOME/.wslconfig" ]; then
        rm "$WINDOWS_HOME/.wslconfig"
        echo "  Removed $WINDOWS_HOME/.wslconfig"
    else
        echo "  Not present, skipping"
    fi

    # --- Step 5: Reload systemd ---
    echo "[5/5] Reloading systemd daemon..."
    systemctl daemon-reload
    echo "  Done"

    echo ""
    echo "=== Revert Complete ==="
    echo ""
    echo "Note: /etc/wsl.conf was NOT reverted (managed by bootstrap)."
    echo "Restart WSL from Windows to apply: wsl --shutdown"
    echo ""
    exit 0
fi

# ============================================================
# Default: apply boot optimizations
# ============================================================
echo ""
echo "=== RevealUI WSL Boot Optimization ==="
echo "Source: $CONFIG_DIR"
echo ""

# --- Step 1: Deploy wsl.conf ---
echo "[1/6] Deploying wsl.conf → /etc/wsl.conf..."
deploy_config "$CONFIG_DIR/wsl.conf" /etc/wsl.conf
echo "  Copied (boot-critical — not symlinked)"

# --- Step 2: Mask unnecessary services ---
echo "[2/6] Masking unnecessary services..."
for svc in "${MASK_SERVICES[@]}"; do
    systemctl mask "$svc" 2>/dev/null || true
done
echo "  Masked ${#MASK_SERVICES[@]} services"

# --- Step 3: Disable heavy auto-start services (keep sockets) ---
echo "[3/6] Disabling heavy auto-start services..."
for svc in "${DISABLE_SERVICES[@]}"; do
    systemctl disable "$svc" 2>/dev/null || true
done
echo "  Disabled ${#DISABLE_SERVICES[@]} services (sockets preserved)"

# --- Step 4: Set default target ---
echo "[4/6] Setting default target to multi-user.target..."
systemctl set-default multi-user.target > /dev/null 2>&1
echo "  Default target: multi-user.target"

# --- Step 5: Deploy .wslconfig to Windows home ---
echo "[5/6] Deploying .wslconfig → Windows home..."
if [ -d "$WINDOWS_HOME" ]; then
    deploy_config "$CONFIG_DIR/wslconfig" "$WINDOWS_HOME/.wslconfig"
    echo "  Copied to $WINDOWS_HOME/.wslconfig"
else
    echo "  WARNING: $WINDOWS_HOME not found, skipping .wslconfig deploy" >&2
fi

# --- Step 6: Reload systemd ---
echo "[6/6] Reloading systemd daemon..."
systemctl daemon-reload
echo "  Done"

echo ""
echo "=== Boot Optimization Complete ==="
echo ""
echo "Restart WSL from Windows to apply:"
echo "  wsl --shutdown"
echo ""
