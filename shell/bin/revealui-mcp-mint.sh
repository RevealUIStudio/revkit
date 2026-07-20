#!/usr/bin/env bash
# revealui-mcp-mint — mint CLI device token into revvault (fleet-owned)
#
# Interactive OTP flow against studio-auth. Canonical secret path:
#   revealui/dev/mcp/cli-token
#
# Usage:
#   rfg mint
#   revealui-mcp-mint.sh
#   REVEALUI_MCP_URL=http://localhost:3004/api/mcp revealui-mcp-mint.sh
#
# Never prints the token. Never writes secrets to git or ~/.grok/config.toml.

set -euo pipefail

VAULT_PATH="${REVEALUI_MCP_TOKEN_VAULT_PATH:-revealui/dev/mcp/cli-token}"
URL="${REVEALUI_MCP_URL:-https://api.revealui.com/api/mcp}"
API_BASE="${URL%/api/mcp}"
API_BASE="${API_BASE%/}"

HOST_SLUG="$(hostname -s 2>/dev/null || hostname | cut -d. -f1)"
DEVICE_ID="${REVEALUI_MCP_DEVICE_ID:-fleet-${HOST_SLUG}-cli}"
DEVICE_NAME="${REVEALUI_MCP_DEVICE_NAME:-RevFleet CLI (${HOST_SLUG})}"
DEVICE_TYPE="cli"

die() { echo "revealui-mcp-mint: $*" >&2; exit 1; }

command -v revvault >/dev/null 2>&1 || die "revvault required"
command -v curl >/dev/null 2>&1 || die "curl required"
command -v python3 >/dev/null 2>&1 || die "python3 required"

echo "RevealUI MCP device mint (Level 1 data plane)"
echo "  api_base=$API_BASE"
echo "  device_id=$DEVICE_ID"
echo "  vault_path=$VAULT_PATH"
echo

if [[ -n "${REVEALUI_EMAIL:-}" ]]; then
  EMAIL="$REVEALUI_EMAIL"
else
  DEFAULT_EMAIL=""
  if DEFAULT_EMAIL="$(revvault get --full revealui/dev/admin-email 2>/dev/null | tr -d '\n')"; then
    :
  else
    DEFAULT_EMAIL=""
  fi
  if [[ -n "$DEFAULT_EMAIL" ]]; then
    read -r -p "Account email [$DEFAULT_EMAIL]: " EMAIL
    EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
  else
    read -r -p "Account email: " EMAIL
  fi
fi

[[ -n "$EMAIL" && "$EMAIL" == *@* ]] || die "valid email required"

export EMAIL DEVICE_ID DEVICE_NAME DEVICE_TYPE
LINK_BODY="$(python3 -c "import json,os; print(json.dumps({'email':os.environ['EMAIL'],'deviceId':os.environ['DEVICE_ID'],'deviceName':os.environ['DEVICE_NAME'],'deviceType':os.environ['DEVICE_TYPE']}))")"
RESP="$(mktemp)"
CODE="$(curl -sS -o "$RESP" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "$LINK_BODY" \
  "${API_BASE}/api/studio-auth/link" || echo "000")"

if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
  echo "link failed HTTP $CODE" >&2
  head -c 300 "$RESP" >&2 || true
  echo >&2
  rm -f "$RESP"
  exit 1
fi
rm -f "$RESP"
echo "OTP sent (if account exists). Expires ~10 minutes."

read -r -p "OTP code: " OTP
OTP="$(echo "$OTP" | tr -d '[:space:]')"
[[ "$OTP" =~ ^[0-9]{4,8}$ ]] || die "OTP should be digits"

export OTP
VERIFY_BODY="$(python3 -c "import json,os; print(json.dumps({'email':os.environ['EMAIL'],'deviceId':os.environ['DEVICE_ID'],'code':os.environ['OTP']}))")"
RESP="$(mktemp)"
CODE="$(curl -sS -o "$RESP" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "$VERIFY_BODY" \
  "${API_BASE}/api/studio-auth/verify" || echo "000")"

if [[ "$CODE" != "200" ]]; then
  echo "verify failed HTTP $CODE" >&2
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('error') or d.get('message') or 'see response')" "$RESP" 2>/dev/null || head -c 200 "$RESP"
  rm -f "$RESP"
  exit 1
fi

TOKEN="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('token') or '')" "$RESP")"
EXPIRES="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('expiresAt') or '')" "$RESP")"
ROLE="$(python3 -c "import json,sys; print((json.load(open(sys.argv[1])).get('user') or {}).get('role') or '')" "$RESP")"
rm -f "$RESP"

[[ "$TOKEN" =~ ^rvui_dev_[0-9a-f]{64}$ ]] || die "verify response missing valid token"

printf '%s' "$TOKEN" | revvault set -f "$VAULT_PATH" || die "revvault set failed for $VAULT_PATH"
TOKEN="$(head -c 32 /dev/urandom | base64 2>/dev/null || echo x)"
unset TOKEN

echo "Stored device token in revvault: $VAULT_PATH"
echo "  expiresAt=${EXPIRES:-unknown}"
echo "  role=${ROLE:-unknown}"
echo
echo "Next: rfg smoke && rfg revealui"
