# RevVault (age-encrypted secret store) configuration
if [ -n "$REVEALUI_ROOT" ] && [ -d "$REVEALUI_ROOT/passage-store" ]; then
    export REVVAULT_STORE="$REVEALUI_ROOT/passage-store"
    export PASSAGE_DIR="$REVVAULT_STORE"
fi
passenv() {
    local varname="$1"
    local path="$2"
    if [ -z "$REVVAULT_STORE" ]; then
        echo "WARN: REVVAULT_STORE not set" >&2
        return 1
    fi
    local val
    val=$(revvault get "$path" 2>/dev/null | head -1)
    if [ -n "$val" ]; then
        export "$varname=$val"
    else
        echo "WARN: revvault get $path failed" >&2
        return 1
    fi
}
passenv-file() {
    local path="$1"
    local content
    content=$(revvault get "$path" 2>/dev/null)
    if [ -z "$content" ]; then
        echo "WARN: revvault get $path failed" >&2
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
