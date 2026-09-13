# shellcheck shell=bash
# revkit-mode — switcher for fleet / vibe / bare (interactive).
#
# Implementation: shell/lib/revkit-mode.sh (resolver) + shell/bin/revkit-mode.sh
# (PATH helper that writes ~/.config/revkit/mode). This wrapper applies the
# mode in the current shell.

revkit-mode() {
  local lib="${REVEALUI_ROOT:-}/shell/lib/revkit-mode.sh"
  if [ ! -f "$lib" ]; then
    echo "revkit-mode: $lib not found (is REVEALUI_ROOT set?)" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  . "$lib"
  case "${1:-}" in
    -h | --help | help)
      revkit_mode_usage
      ;;
    "")
      revkit_mode_print_current
      ;;
    *)
      revkit_mode_set "$1"
      ;;
  esac
}
