#!/bin/bash
# RevealUI WSL Bootstrap
# Run ONCE inside an interactive WSL session:
#   bash /mnt/e/.revealui/bootstrap-wsl.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "=== RevealUI WSL Bootstrap ==="
echo "Source: $SCRIPT_DIR"
echo ""

# --- Step 1: Install helper scripts to /usr/local/bin ---
echo "[1/4] Installing helper scripts to /usr/local/bin..."
for script in "$SCRIPT_DIR/wsl/bin/"*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script")
    # Strip Windows line endings and install
    sed 's/\r$//' "$script" | sudo tee "/usr/local/bin/$name" > /dev/null
    sudo chmod +x "/usr/local/bin/$name"
    echo "  Installed: /usr/local/bin/$name"
done

# --- Step 2: Set up sudoers for passwordless mount ---
echo "[2/4] Configuring sudoers for passwordless mount..."
SUDOERS_FILE="/etc/sudoers.d/wsl-revealui"
CURRENT_USER=$(whoami)
sudo tee "$SUDOERS_FILE" > /dev/null << EOF
# RevealUI - passwordless mount operations
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/local/bin/mount-dev-drive.sh
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/mount
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mount
EOF
sudo chmod 0440 "$SUDOERS_FILE"
if sudo visudo -cf "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "  Sudoers validated"
else
    echo "  ERROR: Sudoers syntax error, removing" >&2
    sudo rm "$SUDOERS_FILE"
    exit 1
fi

# --- Step 3: Add hook to .bashrc ---
echo "[3/4] Adding RevealUI hook to ~/.bashrc..."
MARKER="# --- RevealUI portable dev environment ---"
if grep -qF "$MARKER" ~/.bashrc 2>/dev/null; then
    echo "  Hook already present in ~/.bashrc, skipping"
else
    cat >> ~/.bashrc << 'HOOK'

# --- RevealUI portable dev environment ---
# Source all config fragments from the portable SSD
_revealui_root=""
for _candidate in /mnt/?/.revealui; do
    if [ -f "$_candidate/wsl/bashrc.d/00-base.sh" ]; then
        _revealui_root="$_candidate"
        break
    fi
done
if [ -n "$_revealui_root" ]; then
    for _f in "$_revealui_root"/wsl/bashrc.d/*.sh; do
        [ -r "$_f" ] && . "$_f"
    done
fi
unset _revealui_root _candidate _f
# --- end RevealUI ---
HOOK
    echo "  Hook appended to ~/.bashrc"
fi

# --- Step 4: Link git and SSH configs ---
echo "[4/4] Linking git and SSH configs..."
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

echo ""
echo "=== WSL Bootstrap Complete ==="
echo ""
echo "Restart your shell or run: source ~/.bashrc"
echo ""
