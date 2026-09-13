# shellcheck shell=bash
# vibe prompt — two-line, git-aware. Stream overlay (orthogonal to vibe)
# shows the same stream/VAULT marker as fleet when STREAM_SAFE is on.

__rv_vibe_git() {
  local b
  b=$(git symbolic-ref --short HEAD 2>/dev/null) || b=$(git rev-parse --short HEAD 2>/dev/null) || return
  local d=""
  git diff --quiet HEAD 2>/dev/null || d=" *"
  printf '  %s%s' "$b" "$d"
}

__rv_vibe_stream() {
  if [ "${REVVAULT_ALLOW_PRINT:-}" = "1" ] && [ "${STREAM_SAFE:-}" != "1" ] && [ "${REVVAULT_STREAM_SAFE:-}" != "1" ]; then
    printf '  VAULT'
  elif [ "${STREAM_SAFE:-}" = "1" ] || [ "${REVVAULT_STREAM_SAFE:-}" = "1" ]; then
    printf '  stream'
  fi
}

PS1='\n \[\e[38;2;96;165;250m\]\w\[\e[0m\]\[\e[38;2;52;211;153m\]$(__rv_vibe_git)\[\e[0m\]\[\e[38;2;248;113;113m\]$(__rv_vibe_stream)\[\e[0m\]\n \[\e[38;2;232;121;249m\]❯\[\e[0m\] '
