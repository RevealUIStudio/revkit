# shellcheck shell=bash
# RevVault (age-encrypted secret store) configuration
if [ -n "${REVEALUI_ROOT:-}" ] && [ -d "$REVEALUI_ROOT/passage-store" ]; then
    export REVVAULT_STORE="$REVEALUI_ROOT/passage-store"
    export PASSAGE_DIR="$REVVAULT_STORE"
fi
passenv() {
    local varname="$1"
    local path="$2"

    # Validate variable name: must be a shell identifier (letter/underscore
    # first, then alphanumeric/underscore). POSIX case patterns, not [[ =~ ]],
    # so the guard is identical under bash and zsh and stays regex-free.
    case "$varname" in
        ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*)
            echo "passenv: invalid variable name: $varname" >&2
            return 1
            ;;
    esac

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
    # Capture the FULL secret. Command substitution already strips the single
    # trailing newline; do NOT pipe through `head -1`, which silently truncates
    # multi-line secrets (PEM/SSH private keys, JSON service-account blobs, GPG
    # armor) to their first line while still returning success.
    val="$(revvault get "$path" 2>/dev/null)"
    if [ -n "$val" ]; then
        export "$varname=$val"
    else
        echo "WARN: revvault get $path failed" >&2
        return 1
    fi
}
passenv-file() {
    local path="$1"
    local content line _pf_varname
    content=$(revvault get "$path" 2>/dev/null)
    if [ -z "$content" ]; then
        echo "WARN: revvault get $path failed" >&2
        return 1
    fi
    while IFS= read -r line; do
        # Skip blank lines, comments, and any leading-whitespace line. Keys are
        # honored only at column 0 (the original KEY=value contract).
        case "$line" in
            ''|'#'*|[[:space:]]*) continue ;;
        esac
        # Must be KEY=value.
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        # Capture the key with POSIX parameter expansion, NOT [[ =~ ]] +
        # ${BASH_REMATCH[1]}: under zsh (a real target — bootstrap.sh sources
        # this file into ~/.zshrc) BASH_REMATCH is never populated, so the
        # captured name would be empty, the blocklist below would never match,
        # and a vault env-file could quietly set PATH / LD_PRELOAD /
        # LD_LIBRARY_PATH. Parameter expansion behaves identically under bash
        # and zsh (and keeps this regex-free).
        _pf_varname="${line%%=*}"
        # Reject anything that is not a valid shell identifier.
        case "$_pf_varname" in
            ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) continue ;;
        esac
        # Block dangerous variables
        case "$_pf_varname" in
            PATH|LD_PRELOAD|LD_LIBRARY_PATH|HOME|SHELL|USER|LOGNAME|IFS)
                echo "passenv-file: refusing to override protected variable: $_pf_varname" >&2
                continue
                ;;
        esac
        # shellcheck disable=SC2163  # intentional: $line is "KEY=value", export by literal
        export "$line"
    done <<< "$content"
}
