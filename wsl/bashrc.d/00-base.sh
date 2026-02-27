# RevealUI base environment setup
# Discovers REVEALUI_ROOT and checks dev drive mount status

_find_revealui_root() {
    # Check env var first
    if [ -n "$REVEALUI_ROOT" ] && [ -d "$REVEALUI_ROOT/wsl" ]; then
        echo "$REVEALUI_ROOT"
        return
    fi
    # Primary: C: drive (always available)
    local primary="/mnt/c/Users/joshu/.revealui"
    if [ -f "$primary/wsl/bashrc.d/00-base.sh" ]; then
        echo "$primary"
        return
    fi
    # Fallback: scan single-letter drive mounts (portable SSD)
    for candidate in /mnt/?/.revealui /mnt/?/professional/.revealui; do
        if [ -f "$candidate/wsl/bashrc.d/00-base.sh" ]; then
            echo "$candidate"
            return
        fi
    done
}

export REVEALUI_ROOT="$(_find_revealui_root)"
export REVEALUI_WSL_DEV="/mnt/wsl-dev"

# Dev drive mount check
if [ -d "$REVEALUI_WSL_DEV" ] && mountpoint -q "$REVEALUI_WSL_DEV" 2>/dev/null; then
    export REVEALUI_DEV_MOUNTED=1
else
    unset REVEALUI_DEV_MOUNTED
fi
