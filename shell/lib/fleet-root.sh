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
