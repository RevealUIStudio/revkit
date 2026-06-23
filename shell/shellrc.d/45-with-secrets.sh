# shellcheck shell=bash
# with-secrets <ns...> -- <cmd> [args...]
#
# Runs <cmd> with revvault secrets from the given revealui/env/<ns> namespaces
# loaded into the child process environment only. Nothing leaks back to the
# calling shell.
#
# Usage examples:
#   with-secrets stripe -- pnpm dev:api
#   with-secrets core stripe supabase -- pnpm test:integration
#   with-secrets npm -- pnpm changeset:publish
#   with-secrets core -- pnpm kek:rotate
with-secrets() {
    if [[ $# -eq 0 ]]; then
        printf 'usage: with-secrets <ns...> -- <cmd> [args...]\n' >&2
        return 1
    fi

    local nses=()
    local cmd=()
    local past_sep=0

    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            past_sep=1
            continue
        fi
        if [[ $past_sep -eq 1 ]]; then
            cmd+=("$arg")
        else
            nses+=("$arg")
        fi
    done

    if [[ ${#nses[@]} -eq 0 ]]; then
        printf 'with-secrets: no namespaces given before --\n' >&2
        return 1
    fi

    if [[ ${#cmd[@]} -eq 0 ]]; then
        printf 'with-secrets: no command given after --\n' >&2
        return 1
    fi

    local rv
    rv="$(command -v revvault 2>/dev/null)"
    if [[ -z "$rv" ]]; then
        printf 'with-secrets: revvault not found in PATH\n' >&2
        return 1
    fi

    (
        for ns in "${nses[@]}"; do
            eval "$("$rv" export-env "revealui/env/$ns" 2>/dev/null)" || true
        done
        exec "${cmd[@]}"
    )
}
