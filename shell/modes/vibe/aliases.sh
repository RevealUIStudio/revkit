# shellcheck shell=bash
# vibe aliases — product-first navigation and open helpers.
#
# No tracker / workboard / sync-test / claim completion. rfg and rfc stay
# available as thin PATH wrappers when the helpers are installed.

# REVEALFLEET_ROOT only. The legacy root variable is not read.

alias cdreveal='cd "$REVEALFLEET_ROOT/revealui" 2>/dev/null || echo "cdreveal: RevealUI checkout not found under \$REVEALFLEET_ROOT" >&2'
alias cdfleet='cd "$REVEALFLEET_ROOT" 2>/dev/null || echo "cdfleet: \$REVEALFLEET_ROOT not found" >&2'

_revkit_vibe_helper() {
  local name="$1"
  shift
  local impl=""
  if command -v "${name}.sh" >/dev/null 2>&1; then
    impl="$(command -v "${name}.sh")"
  elif [ -x "/usr/local/bin/${name}.sh" ]; then
    impl="/usr/local/bin/${name}.sh"
  elif [ -x "$HOME/.local/bin/${name}.sh" ]; then
    impl="$HOME/.local/bin/${name}.sh"
  elif [ -n "${REVEALUI_ROOT:-}" ] && [ -x "$REVEALUI_ROOT/shell/bin/${name}.sh" ]; then
    impl="$REVEALUI_ROOT/shell/bin/${name}.sh"
  else
    echo "${name}: ${name}.sh not installed — run bootstrap.sh (or revkit-mode fleet)" >&2
    return 1
  fi
  "$impl" "$@"
}

# Thin wrappers: keep rfg/rfc on the happy PATH without claim-tab noise.
rfc() { _revkit_vibe_helper rfc "$@"; }
rfg() { _revkit_vibe_helper rfg "$@"; }

# Open the product checkout (Claude if rfc is installed).
open-revealui() {
  _revkit_vibe_helper rfc revealui "$@"
}

# Product worktree without claim/acquire. Fleet claims: `revkit-mode fleet`.
create-revealui() {
  if [ -z "${1:-}" ]; then
    echo "usage: create-revealui <label>" >&2
    echo "Creates a RevealUI worktree (no claim). For claim/acquire: revkit-mode fleet" >&2
    return 1
  fi
  _revkit_vibe_helper rfc open revealui "$1" --no-agent
}
