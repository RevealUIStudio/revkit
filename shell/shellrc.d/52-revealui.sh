# shellcheck shell=bash
# revealui — retired PATH name (GAP-351). Short command in managed shells.
#
# Implementation: shell/bin/revealui.sh (installed by bootstrap as
# revealui.sh and as ~/.local/bin/revealui). Prints the rfg/rfc replacement
# and exits 2. Does not start tmux.

revealui() {
  local impl
  if command -v revealui.sh >/dev/null 2>&1; then
    impl="$(command -v revealui.sh)"
  elif [ -x /usr/local/bin/revealui.sh ]; then
    impl=/usr/local/bin/revealui.sh
  elif [ -x "$HOME/.local/bin/revealui.sh" ]; then
    impl="$HOME/.local/bin/revealui.sh"
  elif [ -x "$HOME/.local/bin/revealui" ]; then
    impl="$HOME/.local/bin/revealui"
  elif [ -x "$HOME/revfleet/revkit/shell/bin/revealui.sh" ]; then
    impl="$HOME/revfleet/revkit/shell/bin/revealui.sh"
  else
    echo "revealui: retired — use rfg <repo> (Grok) or rfc <repo> (Claude)" >&2
    return 2
  fi
  "$impl" "$@"
}
