#!/usr/bin/env bash
# kill-audit-storms: PATH wrapper. Implementation lives in shell/lib.
# Bootstrap installs this as kill-audit-storms.sh and as kill-audit-storms.
# shellcheck shell=bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
c=""
for c in \
  "$here/../lib/kill-audit-storms.sh" \
  "$here/../lib/revkit/kill-audit-storms.sh" \
  "/usr/local/lib/revkit/kill-audit-storms.sh" \
  "${REVEALUI_ROOT:-}/shell/lib/kill-audit-storms.sh"
do
  if [ -n "$c" ] && [ -f "$c" ]; then
    exec bash "$c" "$@"
  fi
done
echo "kill-audit-storms: library not found (re-run revkit bootstrap)" >&2
exit 1
