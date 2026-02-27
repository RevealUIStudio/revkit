#!/bin/bash
# RevealUI WSL Boot Optimization
# Idempotent — safe to re-run after config changes.
#
# Usage (from WSL):
#   sudo bash /mnt/e/professional/.revealui/wsl/setup-wsl-boot.sh
#   sudo bash /mnt/e/professional/.revealui/wsl/setup-wsl-boot.sh --revert
#
# After running, restart WSL from Windows:
#   wsl --shutdown

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

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

DISABLE_SERVICES=(
    docker.service
    containerd.service
    snapd.service
    snapd.seeded.service
    snapd.autoimport.service
)

WINDOWS_HOME="/mnt/c/Users/joshu"
DROPIN_DIR="/etc/systemd/system/user@.service.d"

# ============================================================
# --revert: undo all boot optimizations
# ============================================================
if [ "${1:-}" = "--revert" ]; then
    echo ""
    echo "=== Reverting WSL Boot Optimizations ==="
    echo ""

    # --- Step 1: Unmask services ---
    echo "[1/6] Unmasking services..."
    for svc in "${MASK_SERVICES[@]}"; do
        systemctl unmask "$svc" 2>/dev/null || true
    done
    echo "  Unmasked ${#MASK_SERVICES[@]} services"

    # --- Step 2: Re-enable disabled services ---
    echo "[2/6] Re-enabling services..."
    for svc in "${DISABLE_SERVICES[@]}"; do
        systemctl enable "$svc" 2>/dev/null || true
    done
    echo "  Re-enabled ${#DISABLE_SERVICES[@]} services"

    # --- Step 3: Remove login barrier drop-in ---
    echo "[3/6] Removing login barrier override..."
    if [ -f "$DROPIN_DIR/10-login-barrier.conf" ]; then
        rm "$DROPIN_DIR/10-login-barrier.conf"
        rmdir "$DROPIN_DIR" 2>/dev/null || true
        echo "  Removed"
    else
        echo "  Not present, skipping"
    fi

    # --- Step 4: Restore default target ---
    echo "[4/6] Restoring default target to graphical.target..."
    systemctl set-default graphical.target > /dev/null 2>&1
    echo "  Default target: graphical.target"

    # --- Step 5: Remove .wslconfig from Windows home ---
    echo "[5/6] Removing .wslconfig from Windows home..."
    if [ -f "$WINDOWS_HOME/.wslconfig" ]; then
        rm "$WINDOWS_HOME/.wslconfig"
        echo "  Removed $WINDOWS_HOME/.wslconfig"
    else
        echo "  Not present, skipping"
    fi

    # --- Step 6: Reload systemd ---
    echo "[6/6] Reloading systemd daemon..."
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
echo "[1/7] Deploying wsl.conf → /etc/wsl.conf..."
sed 's/\r$//' "$CONFIG_DIR/wsl.conf" > /etc/wsl.conf
echo "  Copied (boot-critical — not symlinked)"

# --- Step 2: Deploy login barrier drop-in ---
echo "[2/7] Deploying user@ login barrier override..."
mkdir -p "$DROPIN_DIR"
sed 's/\r$//' "$CONFIG_DIR/user@-login-barrier.conf" > "$DROPIN_DIR/10-login-barrier.conf"
echo "  Installed: $DROPIN_DIR/10-login-barrier.conf"

# --- Step 3: Mask unnecessary services ---
echo "[3/7] Masking unnecessary services..."
for svc in "${MASK_SERVICES[@]}"; do
    systemctl mask "$svc" 2>/dev/null || true
done
echo "  Masked ${#MASK_SERVICES[@]} services"

# --- Step 4: Disable heavy auto-start services (keep sockets) ---
echo "[4/7] Disabling heavy auto-start services..."
for svc in "${DISABLE_SERVICES[@]}"; do
    systemctl disable "$svc" 2>/dev/null || true
done
echo "  Disabled ${#DISABLE_SERVICES[@]} services (sockets preserved)"

# --- Step 5: Set default target ---
echo "[5/7] Setting default target to multi-user.target..."
systemctl set-default multi-user.target > /dev/null 2>&1
echo "  Default target: multi-user.target"

# --- Step 6: Deploy .wslconfig to Windows home ---
echo "[6/7] Deploying .wslconfig → Windows home..."
if [ -d "$WINDOWS_HOME" ]; then
    sed 's/\r$//' "$CONFIG_DIR/wslconfig" > "$WINDOWS_HOME/.wslconfig"
    echo "  Copied to $WINDOWS_HOME/.wslconfig"
else
    echo "  WARNING: $WINDOWS_HOME not found, skipping .wslconfig deploy" >&2
fi

# --- Step 7: Reload systemd ---
echo "[7/7] Reloading systemd daemon..."
systemctl daemon-reload
echo "  Done"

echo ""
echo "=== Boot Optimization Complete ==="
echo ""
echo "Restart WSL from Windows to apply:"
echo "  wsl --shutdown"
echo ""
