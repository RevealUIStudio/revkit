# shellcheck shell=bash
# RevealUI prompt — two-line, git-aware, nix-aware

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

PS1='\n \[\e[38;2;96;165;250m\]\w\[\e[0m\]\[\e[38;2;52;211;153m\]$(__rv_git)\[\e[0m\]\[\e[38;2;251;191;36m\]$(__rv_nix)\[\e[0m\]\n \[\e[38;2;34;211;238m\]❯\[\e[0m\] '
