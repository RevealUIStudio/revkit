# shellcheck shell=bash
# RevealUI base environment setup
# Discovers REVEALUI_ROOT and checks Sandbox drive mount status

_find_revealui_root() {
    # Bootstrap pin only. Do not scan other users' homes or extra drives.
    if [ -n "${REVEALUI_ROOT:-}" ] && [ -f "${REVEALUI_ROOT}/shell/shellrc.d/00-base.sh" ]; then
        echo "$REVEALUI_ROOT"
        return
    fi
}

_found="$(_find_revealui_root)"
if [ -n "$_found" ]; then
    REVEALUI_ROOT="$_found"
fi
unset _found
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
