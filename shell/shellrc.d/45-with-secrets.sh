# shellcheck shell=bash
# with-secrets <ns...> -- <cmd> [args...]
#
# Runs <cmd> with revvault secrets from the given revealui/env/<ns> namespaces
# loaded into the child process environment only. Nothing leaks back to the
# calling shell.
#
# Usage examples:
#   with-secrets stripe -- pnpm dev:api
#   with-secrets core stripe neon -- pnpm test:integration
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

    local out
    (
        for ns in "${nses[@]}"; do
            # Fail closed. A nonexistent/typo'd namespace, a locked age key, or
            # any other revvault error exits nonzero here. Do NOT swallow it
            # (no 2>/dev/null, no `|| true`): swallowing would let exec run the
            # command with NO secrets loaded, silently — a prod-shaped command
            # stripped of its credentials. Abort the subshell so the caller
            # sees a nonzero status and the command never runs.
            if ! out="$("$rv" export-env "revealui/env/$ns")"; then
                printf 'with-secrets: failed to load namespace %s\n' "$ns" >&2
                exit 1
            fi
            eval "$out"
        done
        exec "${cmd[@]}"
    )
}
