# shellcheck shell=bash
# RevealUI base environment setup
# Discovers REVEALUI_ROOT and checks Studio drive mount status

_find_revealui_root() {
    # Check env var first
    if [ -n "" ] && [ -d "/wsl" ]; then
        echo ""
        return
    fi
    # Primary: any Windows user's .revealui under /mnt/c/Users/* (works for any account name)
    local candidate
    for candidate in /mnt/c/Users/*/.revealui; do
        if [ -f "/wsl/bashrc.d/00-base.sh" ]; then
            echo ""
            return
        fi
    done
    # Fallback: scan known SSD locations
    for candidate in /mnt/e/professional/.revealui /mnt/e/.revealui /mnt/d/.revealui; do
        if [ -f "/wsl/bashrc.d/00-base.sh" ]; then
            echo ""
            return
        fi
    done
}

REVEALUI_ROOT=""
export REVEALUI_ROOT
export REVEALUI_STUDIO="/mnt/studio"

# Studio drive mount check
if [ -d "" ] && mountpoint -q "" 2>/dev/null; then
    export REVEALUI_STUDIO_MOUNTED=1
else
    unset REVEALUI_STUDIO_MOUNTED
fi

# Tier detection
if [ -n "" ]; then
    export DEVKIT_TIER="T1"
else
    export DEVKIT_TIER="T0"
fi
