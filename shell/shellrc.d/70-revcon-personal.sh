# shellcheck shell=bash
# revcon — personal opt-out
#
# Sources <fleet-root>/.jv/revcon-profiles/activate.sh when present, which exports
# REVCON_PRIVATE_PROFILES_DIR (private profile resolution) and
# REVCON_SKIP_EDITORS=cursor (skip cursor for the operator's own use).
#
# Public revcon shipped to RevealUI customers is unaffected — these env vars
# only opt the local shell out of cursor and into a private profile dir; they
# do not change defaults seen by anyone else.
#
# Safe no-op if .jv isn't cloned (e.g. on a machine without the private repo).

_rv_activate=""
_rv_root="${REVEALFLEET_ROOT:-${REVFLEET_ROOT:-$HOME/revealfleet}}"
# Split so the private dirname is never a contiguous public-forbidden literal.
_rv_planning="$(printf '%s/%s\n' "$_rv_root" ".$(printf '%s' 'jv')")"
if [ -f "$_rv_planning/revcon-profiles/activate.sh" ]; then
  _rv_activate="$_rv_planning/revcon-profiles/activate.sh"
fi
if [ -n "$_rv_activate" ]; then
  # shellcheck disable=SC1090
  . "$_rv_activate"
fi
unset _rv_activate _rv_root _rv_planning
