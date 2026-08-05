# shellcheck shell=bash
# RevealUI prompt — two-line, git-aware, nix-aware, stream/vault secret mode

__rv_git() {
    local b
    b=$(git symbolic-ref --short HEAD 2>/dev/null) || b=$(git rev-parse --short HEAD 2>/dev/null) || return
    local d=""
    git diff --quiet HEAD 2>/dev/null || d=" *"
    printf '  %s%s' "$b" "$d"
}

__rv_nix() {
    [ -n "${IN_NIX_SHELL:-}" ] || [ -n "${DIRENV_DIR:-}" ] && printf '  nix'
}

# stream-safe (cyan) vs vault-private allow-print (red) — never print secret values here
__rv_secret_mode() {
    if [ "${REVVAULT_ALLOW_PRINT:-}" = "1" ] && [ "${STREAM_SAFE:-}" != "1" ] && [ "${REVVAULT_STREAM_SAFE:-}" != "1" ]; then
        printf '  VAULT'
    elif [ "${STREAM_SAFE:-}" = "1" ] || [ "${REVVAULT_STREAM_SAFE:-}" = "1" ]; then
        printf '  stream'
    fi
}

PS1='\n \[\e[38;2;96;165;250m\]\w\[\e[0m\]\[\e[38;2;52;211;153m\]$(__rv_git)\[\e[0m\]\[\e[38;2;251;191;36m\]$(__rv_nix)\[\e[0m\]\[\e[38;2;248;113;113m\]$(__rv_secret_mode)\[\e[0m\]\n \[\e[38;2;34;211;238m\]❯\[\e[0m\] '
