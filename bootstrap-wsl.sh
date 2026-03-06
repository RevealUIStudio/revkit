#!/bin/bash
# RevealUI WSL Bootstrap
# Run ONCE inside an interactive WSL session:
#   bash /mnt/c/Users/joshu/.revealui/bootstrap-wsl.sh
#   (or from SSD: bash /mnt/<drive>/.revealui/bootstrap-wsl.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "=== RevealUI WSL Bootstrap ==="
echo "Source: $SCRIPT_DIR"
echo ""

# --- Step 1: Install helper scripts to /usr/local/bin ---
echo "[1/6] Installing helper scripts to /usr/local/bin..."
for script in "$SCRIPT_DIR/wsl/bin/"*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script")
    # Strip Windows line endings and install
    sed 's/\r$//' "$script" | sudo tee "/usr/local/bin/$name" > /dev/null
    sudo chmod +x "/usr/local/bin/$name"
    echo "  Installed: /usr/local/bin/$name"
done

# --- Step 2: Set up sudoers for passwordless mount ---
echo "[2/6] Configuring sudoers for passwordless mount..."
SUDOERS_FILE="/etc/sudoers.d/wsl-revealui"
CURRENT_USER=$(whoami)
sudo tee "$SUDOERS_FILE" > /dev/null << EOF
# RevealUI - passwordless mount operations
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/local/bin/mount-studio-drive.sh
EOF
sudo chmod 0440 "$SUDOERS_FILE"
if sudo visudo -cf "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "  Sudoers validated"
    echo "  NOTE: If upgrading an existing install, run: sudo visudo -f $SUDOERS_FILE"
    echo "        and remove any NOPASSWD lines for /usr/bin/mount and /bin/mount"
else
    echo "  ERROR: Sudoers syntax error, removing" >&2
    sudo rm "$SUDOERS_FILE"
    exit 1
fi

# --- Step 3: Add hook to .bashrc ---
echo "[3/6] Adding RevealUI hook to ~/.bashrc..."
MARKER="# --- RevealUI environment mode ---"
if grep -qF "$MARKER" ~/.bashrc 2>/dev/null; then
    echo "  Hook already present in ~/.bashrc, skipping"
else
    cat >> ~/.bashrc << 'HOOK'

# --- RevealUI environment mode ---
# Guard: only detect and print once per terminal session.
# REVEALUI_MODE is exported, so subshells (e.g. direnv) inherit it
# and skip the detection block entirely.
if [ -z "$REVEALUI_MODE" ]; then
    _revealui_root=""
    # Primary: C: drive (always available)
    if [ -f "/mnt/c/Users/joshu/.revealui/wsl/bashrc.d/00-base.sh" ]; then
        _revealui_root="/mnt/c/Users/joshu/.revealui"
    else
        # Fallback: scan known SSD locations
        for _candidate in /mnt/e/professional/.revealui /mnt/e/.revealui /mnt/d/.revealui; do
            if [ -f "$_candidate/wsl/bashrc.d/00-base.sh" ]; then
                _revealui_root="$_candidate"
                break
            fi
        done
    fi

    if [ -n "$_revealui_root" ]; then
        export REVEALUI_MODE="managed"
        export REVEALUI_ROOT="$_revealui_root"
        for _f in "$_revealui_root"/wsl/bashrc.d/*.sh; do
            [ -r "$_f" ] && . "$_f"
        done
        echo -e "\033[1;36m● RevealUI: managed\033[0m ($_revealui_root)"
    else
        export REVEALUI_MODE="bare"
        unset REVEALUI_ROOT
        echo -e "\033[0;37m● RevealUI: bare\033[0m"
    fi
    unset _revealui_root _candidate _f
fi
# --- end RevealUI ---
HOOK
    echo "  Hook appended to ~/.bashrc"
fi

# --- Step 4: Link git and SSH configs ---
echo "[4/6] Linking git and SSH configs..."
CONFIGS_DIR="$SCRIPT_DIR/wsl/config"

if [ -f "$CONFIGS_DIR/gitconfig" ]; then
    git config --global include.path "$CONFIGS_DIR/gitconfig"
    echo "  Git config: include.path set to $CONFIGS_DIR/gitconfig"
fi

if [ -f "$CONFIGS_DIR/ssh-config" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if ! grep -qF "Include $CONFIGS_DIR/ssh-config" ~/.ssh/config 2>/dev/null; then
        if [ -f ~/.ssh/config ]; then
            TMP=$(mktemp)
            echo "Include $CONFIGS_DIR/ssh-config" > "$TMP"
            echo "" >> "$TMP"
            cat ~/.ssh/config >> "$TMP"
            mv "$TMP" ~/.ssh/config
        else
            echo "Include $CONFIGS_DIR/ssh-config" > ~/.ssh/config
        fi
        chmod 600 ~/.ssh/config
        echo "  SSH config: Include directive added"
    else
        echo "  SSH config: Include already present"
    fi
fi

# --- Step 5: Run boot optimization ---
echo "[5/6] Running boot optimization..."
BOOT_SCRIPT="$SCRIPT_DIR/wsl/setup-wsl-boot.sh"
if [ -f "$BOOT_SCRIPT" ]; then
    sudo bash "$BOOT_SCRIPT"
else
    echo "  WARNING: $BOOT_SCRIPT not found, skipping" >&2
fi

# --- Step 6: Initialize Studio directories ---
if mountpoint -q /mnt/studio 2>/dev/null; then
    echo "[6/6] Initializing Studio directories..."
    mkdir -p /mnt/studio/databases/postgres
    mkdir -p /mnt/studio/databases/redis
    mkdir -p /mnt/studio/databases/supabase
    mkdir -p /mnt/studio/models
    mkdir -p /mnt/studio/cache
    echo "  Studio directories initialized"
else
    echo "[6/6] Studio drive not mounted, skipping directory init"
fi

echo ""
echo "=== WSL Bootstrap Complete ==="
echo ""
echo "Restart your shell or run: source ~/.bashrc"
echo "Then restart WSL from Windows: wsl --shutdown"
echo ""
