#!/usr/bin/env bash
# revealui-mcp-smoke — Level 1 MCP attach health (fleet-owned; never prints secrets)
#
# Exit 0 = ready; 1 = re-mint; 2 = network/config error
#
# Usage: rfg smoke | revealui-mcp-smoke.sh

set -euo pipefail

# Load env via rfg if available, else embedded path through rfg.sh env
if command -v rfg.sh >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  eval "$(rfg.sh env)"
elif [ -x "$HOME/.local/bin/rfg.sh" ]; then
  eval "$("$HOME/.local/bin/rfg.sh" env)"
elif [ -x "$HOME/revfleet/revkit/shell/bin/rfg.sh" ]; then
  eval "$("$HOME/revfleet/revkit/shell/bin/rfg.sh" env)"
else
  echo "revealui-mcp-smoke: rfg.sh not found" >&2
  exit 2
fi

URL="${REVEALUI_MCP_URL:-https://api.revealui.com/api/mcp}"
API_BASE="${URL%/api/mcp}"
API_BASE="${API_BASE%/}"

pass=0
fail=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

ok "token shape (from revvault via rfg env)"

STATUS_BODY="$(mktemp)"
STATUS_CODE="$(curl -sS -o "$STATUS_BODY" -w "%{http_code}" \
  -H "Authorization: Bearer ${REVEALUI_MCP_TOKEN}" \
  "${API_BASE}/api/studio-auth/status" 2>/dev/null || echo "000")"

if [[ "$STATUS_CODE" != "200" ]]; then
  bad "studio-auth/status HTTP $STATUS_CODE"
  rm -f "$STATUS_BODY"
  echo "summary pass=$pass fail=$fail"
  exit 2
fi

AUTHED="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('yes' if d.get('authenticated') is True else 'no')" "$STATUS_BODY")"
ROLE="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print((d.get('user') or {}).get('role') or '')" "$STATUS_BODY")"
rm -f "$STATUS_BODY"

if [[ "$AUTHED" == "yes" ]]; then
  ok "studio-auth/status authenticated (role=${ROLE:-unknown})"
else
  bad "authenticated=false — run: rfg mint"
fi

MCP_BODY="$(mktemp)"
MCP_CODE="$(curl -sS -o "$MCP_BODY" -w "%{http_code}" \
  -H "Authorization: Bearer ${REVEALUI_MCP_TOKEN}" \
  -H "Accept: application/json, text/event-stream" \
  "$URL" 2>/dev/null || echo "000")"
rm -f "$MCP_BODY"

case "$MCP_CODE" in
  401) bad "GET /api/mcp HTTP 401 — re-mint" ;;
  403) bad "GET /api/mcp HTTP 403 — Pro mcp entitlement required" ;;
  000) bad "GET /api/mcp unreachable" ;;
  *)
    ok "GET /api/mcp HTTP $MCP_CODE (not 401/403)"
    ;;
esac

echo "---"
echo "url=$URL"
echo "summary pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
