# shellcheck shell=bash
# fleet-root.sh — resolve the RevealFleet root without using $HOME as a code root.
#
# Trust order (first hit wins):
#   1. REVEALFLEET_ROOT (explicit). Home default is ~/revealfleet only.
#   2. Walk from this file if it still lives in a revkit checkout or worktree
#   3. Matched install pin next to this file (…/lib/revkit/pin.env)
#   4. Walk from REVEALUI_ROOT (bootstrap pin)
# Fail closed if none resolve. Never default to $HOME/revealfleet.
# Fail closed if the resolved fleet root or RFG_WT_ROOT has a path segment
# named revfleet (legacy ~/revfleet). Use REVEALFLEET_ROOT=~/revealfleet.
# Banned paths exit 78. From a command substitution, also signal the caller
# so `$(...) || true` cannot keep the legacy parent.

# True when any path segment is exactly revfleet. revealfleet is a different segment.
rfg_path_has_revfleet_segment() {
  local path="${1:-}"
  local rest seg tilde_prefix
  [ -n "$path" ] || return 1
  # Literal tilde-slash prefix (unexpanded env values). Not a shell tilde expansion.
  tilde_prefix="$(printf '\176')/"
  case "$path" in
    "$tilde_prefix"*) path="${HOME-}/${path#"$tilde_prefix"}" ;;
  esac
  while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do
    path="${path%/}"
  done
  rest="$path"
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    [ "$seg" = "revfleet" ] && return 0
    case "$rest" in
      */*) rest="${rest#*/}" ;;
      *) break ;;
    esac
  done
  return 1
}

rfg_die_banned_fleet_path() {
  local what="${1:-fleet root}"
  printf 'revkit: %s resolves to banned legacy path (segment revfleet). Set REVEALFLEET_ROOT=~/revealfleet\n' "$what" >&2
  # SIGKILL: a trapped SIGTERM, or `$(...) || true`, must not reuse this path.
  if [ "${BASH_SUBSHELL:-0}" -gt 0 ]; then
    kill -s KILL "$$" 2>/dev/null || true
  fi
  exit 78
}

# Die when path, or its physical path when it is a directory, is under revfleet.
rfg_reject_banned_fleet_path() {
  local path="${1:-}"
  local what="${2:-fleet root}"
  local expanded physical tilde_prefix
  [ -n "$path" ] || return 0
  expanded="$path"
  # Literal tilde-slash prefix (unexpanded env values).
  tilde_prefix="$(printf '\176')/"
  case "$expanded" in
    "$tilde_prefix"*) expanded="${HOME-}/${expanded#"$tilde_prefix"}" ;;
  esac
  if rfg_path_has_revfleet_segment "$expanded"; then
    rfg_die_banned_fleet_path "$what"
  fi
  if [ -d "$expanded" ]; then
    physical="$(cd "$expanded" 2>/dev/null && pwd -P)" || physical=""
    if [ -n "$physical" ] && rfg_path_has_revfleet_segment "$physical"; then
      rfg_die_banned_fleet_path "$what"
    fi
  fi
  return 0
}

rfg_infer_fleet_from_path() {
  local start="${1:-}" cur n=0 base parent
  [ -n "$start" ] || return 1
  if [ -f "$start" ]; then
    cur="$(cd "$(dirname "$start")" 2>/dev/null && pwd -P)" || return 1
  elif [ -d "$start" ]; then
    cur="$(cd "$start" 2>/dev/null && pwd -P)" || return 1
  else
    return 1
  fi
  while [ "$n" -lt 16 ] && [ -n "$cur" ] && [ "$cur" != "/" ]; do
    case "$cur" in
      */.wt | */.wt/*)
        parent="${cur%%/.wt*}"
        if [ -n "$parent" ] && [ -d "$parent" ]; then
          rfg_reject_banned_fleet_path "$parent" "fleet root"
          printf '%s\n' "$parent"
          return 0
        fi
        ;;
    esac
    base="${cur##*/}"
    parent="$(dirname "$cur")"
    if [ "$base" = "revkit" ] && [ -f "$cur/shell/lib/fleet-root.sh" ]; then
      rfg_reject_banned_fleet_path "$parent" "fleet root"
      printf '%s\n' "$parent"
      return 0
    fi
    if [ -d "$cur/revkit" ] && [ -f "$cur/revkit/shell/lib/fleet-root.sh" ]; then
      rfg_reject_banned_fleet_path "$cur" "fleet root"
      printf '%s\n' "$cur"
      return 0
    fi
    cur="$parent"
    n=$((n + 1))
  done
  return 1
}

# Install layout is <prefix>/lib/revkit/fleet-root.sh (matched with <prefix>/bin).
# Source-tree layout is <revkit>/shell/lib/fleet-root.sh — no pin file there.
rfg_read_install_pin() {
  local here pin got
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || return 1
  [ "$(basename "$here")" = "revkit" ] || return 1
  [ "$(basename "$(dirname "$here")")" = "lib" ] || return 1
  pin="$here/pin.env"
  [ -f "$pin" ] || return 1
  got="$(
    # shellcheck disable=SC1090
    . "$pin"
    printf '%s\n' "${REVEALFLEET_ROOT:-}"
  )"
  [ -n "$got" ] || return 1
  rfg_reject_banned_fleet_path "$got" "fleet root"
  printf '%s\n' "$got"
}

rfg_resolve_fleet_root() {
  local got rc
  if [ -n "${REVEALFLEET_ROOT:-}" ]; then
    rfg_reject_banned_fleet_path "$REVEALFLEET_ROOT" "fleet root"
    printf '%s\n' "$REVEALFLEET_ROOT"
    return 0
  fi
  rc=0
  got="$(rfg_infer_fleet_from_path "${BASH_SOURCE[0]}")" || rc=$?
  if [ "$rc" -eq 78 ]; then
    rfg_die_banned_fleet_path "fleet root"
  fi
  if [ "$rc" -eq 0 ]; then
    rfg_reject_banned_fleet_path "$got" "fleet root"
    printf '%s\n' "$got"
    return 0
  fi
  rc=0
  got="$(rfg_read_install_pin)" || rc=$?
  if [ "$rc" -eq 78 ]; then
    rfg_die_banned_fleet_path "fleet root"
  fi
  if [ "$rc" -eq 0 ]; then
    rfg_reject_banned_fleet_path "$got" "fleet root"
    printf '%s\n' "$got"
    return 0
  fi
  if [ -n "${REVEALUI_ROOT:-}" ]; then
    rc=0
    got="$(rfg_infer_fleet_from_path "$REVEALUI_ROOT")" || rc=$?
    if [ "$rc" -eq 78 ]; then
      rfg_die_banned_fleet_path "fleet root"
    fi
    if [ "$rc" -eq 0 ]; then
      rfg_reject_banned_fleet_path "$got" "fleet root"
      printf '%s\n' "$got"
      return 0
    fi
  fi
  return 1
}

# True when path is the fleet root or a directory under it.
rfg_path_is_in_fleet() {
  local fleet="${1:-}"
  local path="${2:-}"
  local fleet_real path_real
  [ -n "$fleet" ] && [ -n "$path" ] || return 1
  [ -d "$fleet" ] || return 1
  [ -d "$path" ] || return 1
  fleet_real="$(cd "$fleet" && pwd -P)"
  path_real="$(cd "$path" && pwd -P)"
  case "$path_real" in
    "$fleet_real" | "$fleet_real"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Default worktree parent: <resolved fleet root>/.wt (override with RFG_WT_ROOT).
rfg_wt_root() {
  local fleet rc
  if [ -n "${RFG_WT_ROOT:-}" ]; then
    rfg_reject_banned_fleet_path "$RFG_WT_ROOT" "RFG_WT_ROOT"
    printf '%s\n' "$RFG_WT_ROOT"
    return 0
  fi
  rc=0
  fleet="$(rfg_resolve_fleet_root)" || rc=$?
  if [ "$rc" -eq 78 ]; then
    rfg_die_banned_fleet_path "fleet root"
  fi
  [ "$rc" -eq 0 ] || return 1
  rfg_reject_banned_fleet_path "$fleet" "fleet root"
  rfg_reject_banned_fleet_path "$fleet/.wt" "RFG_WT_ROOT"
  printf '%s/.wt\n' "$fleet"
}

# Resolve rfg/rfc repo argument to an absolute launch directory.
# Sets RFG_LAUNCH_TARGET. RFG_LAUNCH_KEEP_FLAGS=1 when $2 was a flag (keep as argv).
# Status: 0 ok · 1 invalid/missing/escaped · 2 no repo and PWD not in fleet.
rfg_resolve_launch_target() {
  local fleet="$1"
  local repo="${2:-}"
  local here="${3:-$PWD}"
  local target
  RFG_LAUNCH_KEEP_FLAGS=0
  RFG_LAUNCH_TARGET=""
  export RFG_LAUNCH_KEEP_FLAGS RFG_LAUNCH_TARGET
  if [ -z "$repo" ]; then
    if rfg_path_is_in_fleet "$fleet" "$here"; then
      RFG_LAUNCH_TARGET="$here"
      export RFG_LAUNCH_TARGET
      return 0
    fi
    return 2
  fi
  case "$repo" in
    . | ./)
      if rfg_path_is_in_fleet "$fleet" "$here"; then
        RFG_LAUNCH_TARGET="$here"
        export RFG_LAUNCH_TARGET
        return 0
      fi
      return 2
      ;;
    -*)
      if rfg_path_is_in_fleet "$fleet" "$here"; then
        RFG_LAUNCH_TARGET="$here"
        RFG_LAUNCH_KEEP_FLAGS=1
        export RFG_LAUNCH_TARGET RFG_LAUNCH_KEEP_FLAGS
        return 0
      fi
      return 1
      ;;
    .. | ../* | */.. | */../* | /* | */*)
      return 1
      ;;
    *)
      target="$fleet/$repo"
      [ -d "$target" ] || return 1
      rfg_path_is_in_fleet "$fleet" "$target" || return 1
      RFG_LAUNCH_TARGET="$target"
      export RFG_LAUNCH_TARGET
      return 0
      ;;
  esac
}
