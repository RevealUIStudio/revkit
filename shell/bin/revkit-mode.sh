#!/usr/bin/env bash
# revkit-mode — print or persist the RevKit shell mode.
#
# The interactive `revkit-mode` function (shell/shellrc.d/05-revkit-mode.sh)
# applies the mode in the current shell. This PATH helper writes
# ~/.config/revkit/mode (and prints the current mode). A new shell picks it
# up; or run `revkit-mode <mode>` from a fleet/vibe shell to apply immediately.
#
# Usage:
#   revkit-mode                      # print workflow mode + stream overlay
#   revkit-mode fleet|vibe|bare      # write preference file
#   revkit-mode stream-safe          # overlay ON (this process; does not change mode)
#   revkit-mode vault-private        # overlay vault-private (this process)
#   revkit-mode --help

set -euo pipefail

_load_revkit_mode_lib() {
  local here f
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for f in \
    "$here/../lib/revkit-mode.sh" \
    "$(dirname "$here")/lib/revkit/revkit-mode.sh" \
    "${REVEALUI_ROOT:-}/shell/lib/revkit-mode.sh"
  do
    if [ -n "$f" ] && [ -f "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 1
}

if ! _load_revkit_mode_lib; then
  echo "revkit-mode: lib not found (re-run bootstrap.sh or set REVEALUI_ROOT)" >&2
  exit 1
fi

case "${1:-}" in
  -h | --help | help)
    revkit_mode_usage
    exit 0
    ;;
  "")
    revkit_mode_print_current
    exit 0
    ;;
  stream-safe | stream_safe)
    revkit_mode_apply_stream_safe
    revkit_mode_print_current
    printf 'Note: overlay applies to this process; use the revkit-mode shell function to change the current shell.\n' >&2
    exit 0
    ;;
  vault-private | vault_private)
    revkit_mode_apply_vault_private
    revkit_mode_print_current
    printf 'Note: overlay applies to this process; use the revkit-mode shell function to change the current shell.\n' >&2
    exit 0
    ;;
  *)
    if ! _mode="$(revkit_normalize_mode "$1")"; then
      printf 'revkit-mode: unknown mode %s\n' "$1" >&2
      revkit_mode_usage >&2
      exit 1
    fi
    revkit_mode_write_preference "$_mode"
    printf 'revkit-mode: preference set to %s (%s)\n' \
      "$_mode" "$(revkit_mode_preference_path)"
    printf 'Open a new shell to apply, or run `revkit-mode %s` inside a RevKit shell.\n' "$_mode"
    exit 0
    ;;
esac
