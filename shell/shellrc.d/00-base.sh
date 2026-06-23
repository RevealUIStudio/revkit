# shellcheck shell=bash
# RevealUI base environment setup
# Discovers REVEALUI_ROOT and checks Sandbox drive mount status

_find_revealui_root() {
    # Check env var first
    if [ -n "${REVEALUI_ROOT:-}" ] && [ -f "${REVEALUI_ROOT:-}/shell/shellrc.d/00-base.sh" ]; then
        echo "$REVEALUI_ROOT"
        return
    fi
    # Primary: any Windows user's .revealui under /mnt/c/Users/* (works for any account name)
    for candidate in /mnt/c/Users/*/.revealui; do
        if [ -f "$candidate/shell/shellrc.d/00-base.sh" ]; then
            echo "$candidate"
            return
        fi
    done
    # Fallback: scan known SSD locations
    for candidate in /mnt/e/professional/.revealui /mnt/e/.revealui /mnt/d/.revealui; do
        if [ -f "$candidate/shell/shellrc.d/00-base.sh" ]; then
            echo "$candidate"
            return
        fi
    done
}

REVEALUI_ROOT="$(_find_revealui_root)"
export REVEALUI_ROOT
export REVEALUI_SANDBOX="/mnt/sandbox"

# Sandbox drive mount check
if [ -d "$REVEALUI_SANDBOX" ] && mountpoint -q "$REVEALUI_SANDBOX" 2>/dev/null; then
    export REVEALUI_SANDBOX_MOUNTED=1
else
    unset REVEALUI_SANDBOX_MOUNTED
fi

# Tier detection
if [ -n "${REVEALUI_SANDBOX_MOUNTED:-}" ]; then
    export DEVKIT_TIER="T1"
else
    export DEVKIT_TIER="T0"
fi
