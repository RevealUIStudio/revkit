# shellcheck shell=bash
# fleet-root.sh — resolve REVFLEET_ROOT with RevealFleet default + transition
# fallback. Default path is $HOME/revealfleet. Until the owner mv, an existing
# $HOME/revfleet still wins when REVFLEET_ROOT is unset. Explicit REVFLEET_ROOT
# always wins.

rfg_resolve_fleet_root() {
  if [ -n "${REVFLEET_ROOT:-}" ]; then
    printf '%s\n' "$REVFLEET_ROOT"
    return 0
  fi
  if [ -d "${HOME}/revealfleet" ]; then
    printf '%s\n' "${HOME}/revealfleet"
    return 0
  fi
  if [ -d "${HOME}/revfleet" ]; then
    printf '%s\n' "${HOME}/revfleet"
    return 0
  fi
  printf '%s\n' "${HOME}/revealfleet"
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

# Default worktree parent: <fleet-root>/.wt (override with RFG_WT_ROOT).
rfg_wt_root() {
  if [ -n "${RFG_WT_ROOT:-}" ]; then
    printf '%s\n' "$RFG_WT_ROOT"
    return 0
  fi
  printf '%s/.wt\n' "$(rfg_resolve_fleet_root)"
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
  if [ -z "$repo" ]; then
    if rfg_path_is_in_fleet "$fleet" "$here"; then
      RFG_LAUNCH_TARGET="$here"
      return 0
    fi
    return 2
  fi
  case "$repo" in
    . | ./)
      if rfg_path_is_in_fleet "$fleet" "$here"; then
        RFG_LAUNCH_TARGET="$here"
        return 0
      fi
      return 2
      ;;
    -*)
      if rfg_path_is_in_fleet "$fleet" "$here"; then
        RFG_LAUNCH_TARGET="$here"
        RFG_LAUNCH_KEEP_FLAGS=1
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
      return 0
      ;;
  esac
}
