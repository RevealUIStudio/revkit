# shellcheck shell=bash
# revcon — personal opt-out
#
# Sources <planning-checkout>/revcon-profiles/activate.sh when present, which exports
# REVCON_PRIVATE_PROFILES_DIR (private profile resolution) and
# REVCON_SKIP_EDITORS=cursor (skip cursor for the operator's own use).
#
# Public revcon shipped to RevealUI customers is unaffected — these env vars
# only opt the local shell out of cursor and into a private profile dir; they
# do not change defaults seen by anyone else.
#
# Safe no-op when REVEALFLEET_PLANNING is not configured.

_rv_activate=""
_rv_planning=""
if [ -n "${REVEALFLEET_PLANNING:-}" ]; then
  _rv_planning="$(__rv_planning_root)" || return 1
  if [ -f "$_rv_planning/revcon-profiles/activate.sh" ]; then
    _rv_activate="$_rv_planning/revcon-profiles/activate.sh"
  fi
fi
if [ -n "$_rv_activate" ]; then
  # shellcheck disable=SC1090
  . "$_rv_activate"
fi
unset _rv_activate _rv_planning
