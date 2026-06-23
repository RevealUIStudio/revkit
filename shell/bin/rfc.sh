#!/usr/bin/env bash
# rfc — RevFleet Claude launcher (WSL / native Linux / macOS)
#
# Starts a `claude` session rooted in a RevFleet repo, running in the current
# POSIX shell. On WSL this is the entire point: claude's Bash tool-calls run
# native (`git status`, not `wsl.exe -d Ubuntu -- bash -lc '... git status'`) —
# the wsl.exe wrapper is (a) un-allowlistable (the payload is an opaque string,
# so only `Bash(wsl.exe *)` covers it, equivalent to bypassPermissions) and
# (b) slips past the PreToolUse deny-list hook; launching in WSL instead means
# commands allowlist by real prefix AND the deny-list + hooks fire. On native
# Linux/macOS there is no wrapper to defeat, so rfc is simply a thin cd + exec
# convenience. See docs/rfc-launcher.md for the full per-surface rationale.
#
# Usage:
#   rfc                  # use $PWD if it is under ~/revfleet, else list repos
#   rfc revealui         # cd ~/revfleet/revealui && exec claude
#   rfc revealui --continue   # trailing args pass through to claude verbatim
#
# Reusable across machines: bootstrap installs this to /usr/local/bin (WSL/
# Linux) or ~/.local/bin (macOS); the short `rfc` command, `rf`/`rfclaude`
# aliases, and completion come from shell/shellrc.d/50-rfc.sh. Override the
# fleet root with REVFLEET_ROOT.

set -euo pipefail

FLEET_ROOT="${REVFLEET_ROOT:-$HOME/revfleet}"

die() { echo "rfc: $*" >&2; exit 1; }

# Run only in a real POSIX shell (WSL/Linux or macOS). Reject Git Bash / cmd
# on the Windows host (uname MINGW*/CYGWIN*), where launching here would defeat
# the purpose rather than run claude natively.
case "$(uname -s 2>/dev/null)" in
  Linux | Darwin) : ;;
  *) die "must run in a POSIX shell (WSL, Linux, or macOS); not Git Bash/cmd" ;;
esac
[ -d "$FLEET_ROOT" ] || die "fleet root not found: $FLEET_ROOT (set REVFLEET_ROOT)"

# Resolve the claude binary: prefer PATH, then the known override locations.
# (~/.local/bin.override/claude is the fnm-managed shim used by this machine.)
resolve_claude() {
  if command -v claude >/dev/null 2>&1; then command -v claude; return 0; fi
  local c
  for c in "$HOME/.local/bin.override/claude" "$HOME/.local/bin/claude"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

list_repos() {
  local d
  # Plain dirs plus dotted repos; only those with a .git entry.
  for d in "$FLEET_ROOT"/*/ "$FLEET_ROOT"/.*/; do
    [ -e "${d}.git" ] || continue
    d="${d%/}"; echo "  ${d##*/}"
  done
}

repo="${1:-}"
[ -n "$repo" ] && shift

if [ -z "$repo" ]; then
  # No repo given: use the current fleet repo if we're inside one, else list.
  case "$PWD/" in
    "$FLEET_ROOT"/*) target="$PWD" ;;
    *)
      echo "rfc: name a fleet repo, e.g. 'rfc revealui'. Available:" >&2
      list_repos >&2
      exit 2 ;;
  esac
else
  target="$FLEET_ROOT/$repo"
  [ -d "$target" ] || die "no such fleet repo: '$repo' (under $FLEET_ROOT)"
fi

claude_bin="$(resolve_claude)" || die "claude not found on PATH or in ~/.local/bin*"

cd "$target"
exec "$claude_bin" "$@"
