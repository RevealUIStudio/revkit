# shellcheck shell=bash
# RevVault (age-encrypted secret store) configuration
if [ -n "${REVEALUI_ROOT:-}" ] && [ -d "$REVEALUI_ROOT/passage-store" ]; then
    export REVVAULT_STORE="$REVEALUI_ROOT/passage-store"
    export PASSAGE_DIR="$REVVAULT_STORE"
fi
passenv() {
    local varname="$1"
    local path="$2"

    # Validate variable name: alphanumeric + underscore only, must start with letter/underscore
    if [[ ! "$varname" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "passenv: invalid variable name: $varname" >&2
        return 1
    fi

    # Block dangerous variables
    case "$varname" in
        PATH|LD_PRELOAD|LD_LIBRARY_PATH|HOME|SHELL|USER|LOGNAME|IFS)
            echo "passenv: refusing to override protected variable: $varname" >&2
            return 1
            ;;
    esac

    if [ -z "${REVVAULT_STORE:-}" ]; then
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
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            local _pf_varname="${BASH_REMATCH[1]}"
            # Block dangerous variables
            case "$_pf_varname" in
                PATH|LD_PRELOAD|LD_LIBRARY_PATH|HOME|SHELL|USER|LOGNAME|IFS)
                    echo "passenv-file: refusing to override protected variable: $_pf_varname" >&2
                    continue
                    ;;
            esac
            # shellcheck disable=SC2163  # intentional: $line is "KEY=value", export by literal
            export "$line"
        fi
    done <<< "$content"
}
