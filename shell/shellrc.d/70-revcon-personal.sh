# shellcheck shell=bash
# revcon — personal opt-out
#
# Sources ~/revfleet/.jv/revcon-profiles/activate.sh when present, which exports
# REVCON_PRIVATE_PROFILES_DIR (private profile resolution) and
# REVCON_SKIP_EDITORS=cursor (skip cursor for the operator's own use).
#
# Public revcon shipped to RevealUI customers is unaffected — these env vars
# only opt the local shell out of cursor and into a private profile dir; they
# do not change defaults seen by anyone else.
#
# Safe no-op if .jv isn't cloned (e.g. on a machine without the private repo).

if [ -f "$HOME/revfleet/.jv/revcon-profiles/activate.sh" ]; then
  . "$HOME/revfleet/.jv/revcon-profiles/activate.sh"
fi
