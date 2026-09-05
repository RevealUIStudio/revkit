# shellcheck shell=bash
# rfg — RevFleet Grok launcher: short command + completion (interactive).
#
# Implementation: shell/bin/rfg.sh (installed by bootstrap to /usr/local/bin
# or ~/.local/bin). Loads RevealUI MCP token from revvault and execs grok.
# See docs/rfg-launcher.md.

rfg() {
  local impl
  if command -v rfg.sh >/dev/null 2>&1; then
    impl="$(command -v rfg.sh)"
  elif [ -x /usr/local/bin/rfg.sh ]; then
    impl=/usr/local/bin/rfg.sh
  elif [ -x "$HOME/.local/bin/rfg.sh" ]; then
    impl="$HOME/.local/bin/rfg.sh"
  elif [ -n "${REVEALUI_ROOT:-}" ] && [ -x "$REVEALUI_ROOT/shell/bin/rfg.sh" ]; then
    impl="$REVEALUI_ROOT/shell/bin/rfg.sh"
  elif [ -x "$HOME/revfleet/revkit/shell/bin/rfg.sh" ]; then
    impl="$HOME/revfleet/revkit/shell/bin/rfg.sh"
  else
    echo "rfg: rfg.sh not installed — re-run revkit bootstrap.sh or: ln -s ~/revfleet/revkit/shell/bin/rfg.sh ~/.local/bin/rfg.sh" >&2
    return 1
  fi
  "$impl" "$@"
}

# Muscle memory / parallel to rf/rfclaude
alias rfgrok='rfg'
alias grok-rv='rfg'

# Bash tab-completion: first arg = fleet repo (same as rfc)
if [ -n "${BASH_VERSION:-}" ] && command -v complete >/dev/null 2>&1; then
  _rfg_complete() {
    [ "${COMP_CWORD:-0}" -eq 1 ] || return 0
    local root="${REVFLEET_ROOT:-}"
    if [ -z "$root" ]; then
      if [ -d "$HOME/revealfleet" ]; then root="$HOME/revealfleet"
      elif [ -d "$HOME/revfleet" ]; then root="$HOME/revfleet"
      else root="$HOME/revealfleet"
      fi
    fi
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local d repos=(mint smoke env bootstrap claim open help)
    for d in "$root"/*/ "$root"/.*/; do
      [ -e "${d}.git" ] || continue
      d="${d%/}"; repos+=("${d##*/}")
    done
    mapfile -t COMPREPLY < <(compgen -W "${repos[*]}" -- "$cur")
  }
  complete -F _rfg_complete rfg
  complete -F _rfg_complete rfgrok
fi
