# shellcheck shell=bash
# RevealUI base environment setup
_find_revealui_root() {
    if [ -n "${REVEALUI_ROOT:-}" ] && [ -d "${REVEALUI_ROOT:-}/wsl" ]; then
        echo "$REVEALUI_ROOT"
        return
    fi
    local primary="$HOME/.revealui"
    if [ -f "$primary/wsl/bashrc.d/00-base.sh" ]; then
        echo "$primary"
        return
    fi
    local ntfs="/mnt/c/Users/{{WINDOWS_USER}}/.revealui"
    if [ -f "$ntfs/wsl/bashrc.d/00-base.sh" ]; then
        echo "$ntfs"
        return
    fi
    for candidate in /mnt/e/professional/.revealui /mnt/e/.revealui /mnt/d/.revealui; do
        if [ -f "$candidate/wsl/bashrc.d/00-base.sh" ]; then
            echo "$candidate"
            return
        fi
    done
}
export REVEALUI_ROOT="$(_find_revealui_root)"
export REVEALUI_STUDIO="{{STUDIO_MOUNT}}"
# Studio drive mount check
if [ -d "$REVEALUI_STUDIO" ] && mountpoint -q "$REVEALUI_STUDIO" 2>/dev/null; then
    export REVEALUI_STUDIO_MOUNTED=1
else
    unset REVEALUI_STUDIO_MOUNTED
fi
# Tier detection
if [ -n "${REVEALUI_STUDIO_MOUNTED:-}" ]; then
    export DEVKIT_TIER="T1"
else
    export DEVKIT_TIER="T0"
fi
