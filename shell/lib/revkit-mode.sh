# shellcheck shell=bash
# revkit-mode.sh — resolve and apply RevKit shell modes (fleet / vibe / bare).
#
# Resolution: REVEALUI_MODE env > ~/.config/revkit/mode > fleet default.
# Compat: managed is a silent alias for fleet (documented, no warning).
# Sourced by the rc hook, shell/bin/revkit-mode.sh, and the revkit-mode() wrapper.

revkit_mode_preference_path() {
  printf '%s/revkit/mode\n' "${XDG_CONFIG_HOME:-${HOME}/.config}"
}

# Map a raw token to fleet|vibe|bare. Returns 1 for unknown values.
revkit_normalize_mode() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$raw" in
    fleet | vibe | bare)
      printf '%s\n' "$raw"
      ;;
    managed)
      printf '%s\n' "fleet"
      ;;
    *)
      return 1
      ;;
  esac
}

# Print the canonical mode for this process (env > preference file > fleet).
revkit_resolve_mode() {
  local raw="" pref
  if [ -n "${REVEALUI_MODE:-}" ]; then
    raw="$REVEALUI_MODE"
  else
    pref="$(revkit_mode_preference_path)"
    if [ -f "$pref" ]; then
      raw="$(tr -d '[:space:]' < "$pref")"
    fi
  fi
  if [ -z "$raw" ]; then
    printf '%s\n' "fleet"
    return 0
  fi
  if revkit_normalize_mode "$raw"; then
    return 0
  fi
  printf 'revkit: unknown mode %s - defaulting to fleet\n' "$raw" >&2
  printf '%s\n' "fleet"
}

revkit_mode_write_preference() {
  local mode="$1" pref dir
  mode="$(revkit_normalize_mode "$mode")" || return 1
  pref="$(revkit_mode_preference_path)"
  dir="$(dirname "$pref")"
  mkdir -p "$dir"
  printf '%s\n' "$mode" > "$pref"
}

# Expand a modes/*.list into readable fragment paths (one per line).
# Lines are relative to $REVEALUI_ROOT/shell/. A bare filename is
# shellrc.d/<name>. Missing files are skipped. The only glob supported
# is a trailing *.sh (fleet's "all fragments" contract).
revkit_mode_list_paths() {
  local mode="${1:-}" list line rel dir base path root
  root="${REVEALUI_ROOT:-}"
  [ -n "$root" ] || return 1
  list="$root/shell/modes/${mode}.list"
  if [ ! -f "$list" ]; then
    if [ "$mode" = "fleet" ]; then
      for path in "$root/shell/shellrc.d"/*.sh; do
        [ -r "$path" ] && printf '%s\n' "$path"
      done
    fi
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    case "$line" in
      '' | \#*) continue ;;
    esac
    case "$line" in
      */*) rel="$line" ;;
      *) rel="shellrc.d/$line" ;;
    esac
    base="${rel##*/}"
    if [ "$base" = "*.sh" ]; then
      dir="$root/shell/${rel%/*}"
      for path in "$dir"/*.sh; do
        [ -r "$path" ] && printf '%s\n' "$path"
      done
    else
      path="$root/shell/$rel"
      [ -r "$path" ] && printf '%s\n' "$path"
    fi
  done < "$list"
}

revkit_mode_source_fragments() {
  local mode="${1:-}" _f
  while IFS= read -r _f; do
    [ -r "$_f" ] || continue
    # shellcheck disable=SC1090
    . "$_f"
  done <<EOF
$(revkit_mode_list_paths "$mode")
EOF
  unset _f
}

revkit_mode_print_banner() {
  local mode="${1:-}"
  case "$mode" in
    fleet)
      printf '\033[1;36m● RevKit: fleet\033[0m (%s)\n' "${REVEALUI_ROOT:-}"
      ;;
    vibe)
      printf '\033[1;35m● RevKit: vibe\033[0m (%s)\n' "${REVEALUI_ROOT:-}"
      ;;
    bare)
      printf '\033[0;37m● RevKit: bare\033[0m\n'
      ;;
    *)
      printf '\033[0;37m● RevKit: %s\033[0m\n' "$mode"
      ;;
  esac
}

revkit_mode_print_vibe_tip() {
  printf 'vibe mode - product-first; `revkit-mode fleet` for full fleet tooling\n'
}

revkit_mode_usage() {
  cat <<'EOF'
usage:
  revkit-mode                      # print workflow mode + stream overlay
  revkit-mode fleet|vibe|bare      # set workflow mode (this shell + ~/.config/revkit/mode)
  revkit-mode stream-safe          # stream overlay ON (does not change REVEALUI_MODE)
  revkit-mode vault-private        # stream overlay off / vault-private (does not change REVEALUI_MODE)

workflow modes:
  fleet  full engineer/fleet workflow (all shell/shellrc.d/*.sh)
  vibe   product-first subset (see shell/modes/vibe.list)
  bare   no fragments (escape hatch)

stream overlay (orthogonal; not a fourth REVEALUI_MODE):
  stream-safe     STREAM_SAFE=1; no TTY print/clip of secrets
  vault-private   REVVAULT_ALLOW_PRINT=1; keep this window out of OBS
  off             neither (default)

managed is a deprecated alias for fleet (silent map).
Default when unset: fleet (not vibe).
There is no REVEALUI_MODE=stream.
EOF
}

# Overlay state: stream-safe | vault-private | off
revkit_mode_stream_state() {
  if [ "${REVVAULT_ALLOW_PRINT:-}" = "1" ] && [ "${STREAM_SAFE:-}" != "1" ] && [ "${REVVAULT_STREAM_SAFE:-}" != "1" ]; then
    printf '%s\n' "vault-private"
  elif [ "${STREAM_SAFE:-}" = "1" ] || [ "${REVVAULT_STREAM_SAFE:-}" = "1" ]; then
    printf '%s\n' "stream-safe"
  else
    printf '%s\n' "off"
  fi
}

revkit_mode_print_current() {
  printf 'mode: %s\n' "$(revkit_resolve_mode)"
  printf 'stream: %s\n' "$(revkit_mode_stream_state)"
}

# Same exports as shell/shellrc.d/42-stream-safe.sh. Does not touch REVEALUI_MODE.
revkit_mode_ensure_stream_helpers() {
  if type stream-safe >/dev/null 2>&1 && type vault-private >/dev/null 2>&1; then
    return 0
  fi
  local f="${REVEALUI_ROOT:-}/shell/shellrc.d/42-stream-safe.sh"
  if [ -r "$f" ]; then
    # shellcheck disable=SC1090
    . "$f"
  fi
}

revkit_mode_apply_stream_safe() {
  revkit_mode_ensure_stream_helpers
  if type stream-safe >/dev/null 2>&1; then
    stream-safe
  else
    export STREAM_SAFE=1
    export REVVAULT_STREAM_SAFE=1
    unset REVVAULT_ALLOW_PRINT 2>/dev/null || true
    printf 'stream-safe ON: secrets only via revvault run / with-secrets (no TTY print/clip).\n' >&2
  fi
}

revkit_mode_apply_vault_private() {
  revkit_mode_ensure_stream_helpers
  if type vault-private >/dev/null 2>&1; then
    vault-private
  else
    unset STREAM_SAFE REVVAULT_STREAM_SAFE 2>/dev/null || true
    export REVVAULT_ALLOW_PRINT=1
    printf 'vault-private ON: full get/clip allowed. Keep this window out of OBS.\n' >&2
  fi
}

# RV_STREAM=1 from a terminal profile enables stream-safe without changing mode.
# Mirrors 42-stream-safe.sh so vibe/bare (which do not source that fragment) still honor it.
revkit_mode_honor_rv_stream() {
  if [ "${RV_STREAM:-}" = "1" ] && [ -z "${REVVAULT_ALLOW_PRINT:-}" ]; then
    export STREAM_SAFE=1
    export REVVAULT_STREAM_SAFE=1
  fi
}

# Apply the resolved mode: source fragments, export, banner.
# Once-per-session: callers gate on REVEALUI_SHELL_READY.
revkit_mode_activate() {
  local mode
  if [ ! -f "${REVEALUI_ROOT:-}/shell/shellrc.d/00-base.sh" ]; then
    export REVEALUI_MODE="bare"
    export REVEALUI_SHELL_READY=1
    revkit_mode_honor_rv_stream
    revkit_mode_print_banner bare
    return 0
  fi
  mode="$(revkit_resolve_mode)"
  export REVEALUI_MODE="$mode"
  if [ "$mode" != "bare" ]; then
    revkit_mode_source_fragments "$mode"
  fi
  revkit_mode_honor_rv_stream
  revkit_mode_print_banner "$mode"
  if [ "$mode" = "vibe" ]; then
    revkit_mode_print_vibe_tip
  fi
  export REVEALUI_SHELL_READY=1
}

# Switch the current shell and persist the preference.
revkit_mode_set() {
  local mode requested="${1:-}"
  if ! mode="$(revkit_normalize_mode "$requested")"; then
    printf 'revkit-mode: unknown mode %s\n' "$requested" >&2
    revkit_mode_usage >&2
    return 1
  fi
  revkit_mode_write_preference "$mode" || return 1
  export REVEALUI_MODE="$mode"
  if [ "$mode" != "bare" ]; then
    if [ ! -f "${REVEALUI_ROOT:-}/shell/shellrc.d/00-base.sh" ]; then
      printf 'revkit-mode: REVEALUI_ROOT missing 00-base.sh; staying bare\n' >&2
      export REVEALUI_MODE="bare"
      revkit_mode_print_banner bare
      export REVEALUI_SHELL_READY=1
      return 1
    fi
    revkit_mode_source_fragments "$mode"
  fi
  revkit_mode_honor_rv_stream
  revkit_mode_print_banner "$mode"
  if [ "$mode" = "vibe" ]; then
    revkit_mode_print_vibe_tip
  fi
  if [ -n "${REVEALUI_SHELL_READY:-}" ]; then
    printf 'Note: already-loaded fragments stay until you open a new shell.\n' >&2
  fi
  export REVEALUI_SHELL_READY=1
}
