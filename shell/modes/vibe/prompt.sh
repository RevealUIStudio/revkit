# shellcheck shell=bash
# vibe prompt — two-line, git-aware, no vault/stream ceremony.

__rv_vibe_git() {
  local b
  b=$(git symbolic-ref --short HEAD 2>/dev/null) || b=$(git rev-parse --short HEAD 2>/dev/null) || return
  local d=""
  git diff --quiet HEAD 2>/dev/null || d=" *"
  printf '  %s%s' "$b" "$d"
}

PS1='\n \[\e[38;2;96;165;250m\]\w\[\e[0m\]\[\e[38;2;52;211;153m\]$(__rv_vibe_git)\[\e[0m\]\n \[\e[38;2;232;121;249m\]❯\[\e[0m\] '
