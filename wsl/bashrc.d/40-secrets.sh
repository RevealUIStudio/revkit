# Passage (age-encrypted password store) configuration
# Requires: age, passage installed via nix

# Point passage at the SSD store
if [ -n "$REVEALUI_ROOT" ] && [ -d "$REVEALUI_ROOT/passage-store" ]; then
    export PASSAGE_DIR="$REVEALUI_ROOT/passage-store"
fi

# Helper: load a passage entry as an env var
# Usage: passenv VAR_NAME passage/path
passenv() {
    local varname="$1"
    local path="$2"
    if [ -z "$PASSAGE_DIR" ]; then
        echo "WARN: PASSAGE_DIR not set" >&2
        return 1
    fi
    local val
    val=$(passage show "$path" 2>/dev/null | head -1)
    if [ -n "$val" ]; then
        export "$varname=$val"
    else
        echo "WARN: passage show $path failed" >&2
        return 1
    fi
}

# Helper: source multi-line .env from passage
# Usage: passenv-file revealui/env/streetbeefs-scrapyard
passenv-file() {
    local path="$1"
    local content
    content=$(passage show "$path" 2>/dev/null)
    if [ -z "$content" ]; then
        echo "WARN: passage show $path failed" >&2
        return 1
    fi
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            export "$line"
        fi
    done <<< "$content"
}
