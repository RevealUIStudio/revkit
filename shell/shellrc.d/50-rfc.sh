# shellcheck shell=bash
# rfc — RevFleet Claude launcher: short command + completion (interactive).
#
# The robust implementation lives at /usr/local/bin/rfc.sh (deployed by
# bootstrap.sh). This file — auto-sourced in managed interactive
# shells via the ~/.bashrc hook — just provides the short `rfc` name and
# tab-completion over ~/revfleet/* repos. See docs/rfc-launcher.md.

rfc() {
  local impl
  if command -v rfc.sh >/dev/null 2>&1; then
    impl="$(command -v rfc.sh)"
  elif [ -x /usr/local/bin/rfc.sh ]; then
    impl=/usr/local/bin/rfc.sh
  elif [ -x "$HOME/.local/bin/rfc.sh" ]; then
    impl="$HOME/.local/bin/rfc.sh"
  else
    echo "rfc: rfc.sh not installed — run bootstrap.sh" >&2
    return 1
  fi
  "$impl" "$@"
}

# Muscle-memory aliases — rfc is the single canonical launcher. If you have
# personal rf/rfclaude shell functions predating RevKit, delete them so these
# canonical aliases win regardless of source order.
alias rf='rfc'
alias rfclaude='rfc'

# Bash tab-completion over ~/revfleet/* — bash only. zsh has its own completion
# system and lacks complete/compgen/mapfile, so this block no-ops there.
if [ -n "${BASH_VERSION:-}" ] && command -v complete >/dev/null 2>&1; then
  _rfc_complete() {
    # Only complete the first argument (repo name or rfc subcommand).
    [ "${COMP_CWORD:-0}" -eq 1 ] || return 0
    local root="${REVFLEET_ROOT:-}"
    if [ -z "$root" ]; then
      if [ -d "$HOME/revealfleet" ]; then root="$HOME/revealfleet"
      elif [ -d "$HOME/revfleet" ]; then root="$HOME/revfleet"
      else root="$HOME/revealfleet"
      fi
    fi
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local d repos=()
    for d in "$root"/*/ "$root"/.*/; do
      [ -e "${d}.git" ] || continue
      d="${d%/}"; repos+=("${d##*/}")
    done
    mapfile -t COMPREPLY < <(compgen -W "mint smoke env bootstrap claim open help ${repos[*]}" -- "$cur")
  }
  complete -F _rfc_complete rfc
fi
