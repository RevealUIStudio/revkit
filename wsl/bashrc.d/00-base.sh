# RevealUI base environment setup
# Discovers REVEALUI_ROOT and checks Forge drive mount status

_find_revealui_root() {
    # Check env var first
    if [ -n "${REVEALUI_ROOT:-}" ] && [ -d "${REVEALUI_ROOT:-}/wsl" ]; then
        echo "$REVEALUI_ROOT"
        return
    fi
    # Primary: C: drive (always available)
    local primary="/mnt/c/Users/joshu/.revealui"
    if [ -f "$primary/wsl/bashrc.d/00-base.sh" ]; then
        echo "$primary"
        return
    fi
    # Fallback: scan known SSD locations
    for candidate in /mnt/e/professional/.revealui /mnt/e/.revealui /mnt/d/.revealui; do
        if [ -f "$candidate/wsl/bashrc.d/00-base.sh" ]; then
            echo "$candidate"
            return
        fi
    done
}

export REVEALUI_ROOT="$(_find_revealui_root)"
export REVEALUI_FORGE="/mnt/forge"

# Forge drive mount check
if [ -d "$REVEALUI_FORGE" ] && mountpoint -q "$REVEALUI_FORGE" 2>/dev/null; then
    export REVEALUI_FORGE_MOUNTED=1
else
    unset REVEALUI_FORGE_MOUNTED
fi

# Tier detection
if [ -n "${REVEALUI_FORGE_MOUNTED:-}" ]; then
    export DEVKIT_TIER="T1"
else
    export DEVKIT_TIER="T0"
fi
