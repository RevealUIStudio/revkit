#!/usr/bin/env bash
# test-rfg-env.sh — rfg env must never emit REVEALUI_MCP_TOKEN (stdout or stderr).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RFG="$ROOT/shell/bin/rfg.sh"
SMOKE="$ROOT/shell/bin/revealui-mcp-smoke.sh"
MINT="$ROOT/shell/bin/revealui-mcp-mint.sh"
DOCS="$ROOT/docs/rfg-launcher.md"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Synthetic device-token shape (rvui_dev_ + 64 hex = 73). Not a live secret.
FAKE_TOKEN="rvui_dev_$(printf 'ab%.0s' {1..32})"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/revvault" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "get" ]; then
  printf '%s' '$FAKE_TOKEN'
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/revvault"

# Stub first so a real revvault on the runner cannot supply a live token.
export PATH="$TMP/bin:/usr/bin:/bin"
unset REVEALUI_MCP_TOKEN || true
unset REVEALUI_MCP_ENV_SKIP || true

echo "=== test-rfg-env.sh ==="
echo "Source:   $RFG"
echo ""

echo "--- Behavioral: rfg env with stubbed vault ---"

errfile="$TMP/err"
out="$(bash "$RFG" env 2>"$errfile")" && rc=0 || rc=$?
err="$(cat "$errfile")"

if [ "$rc" -eq 0 ]; then
  pass "rfg env exits 0 when vault returns a valid token"
else
  fail "rfg env exit $rc stderr=$err"
fi

combined="$out"$'\n'"$err"
if [[ "$combined" == *"$FAKE_TOKEN"* ]]; then
  fail "rfg env emitted the token on stdout or stderr"
else
  pass "rfg env does not emit the token on stdout or stderr"
fi

if [[ "$combined" == *rvui_dev_* ]]; then
  fail "rfg env emitted a device-token prefix"
else
  pass "rfg env does not emit a device-token prefix"
fi

if [[ "$out" == *"REVEALUI_MCP_TOKEN="* ]] || [[ "$err" == *"REVEALUI_MCP_TOKEN="* ]]; then
  fail "rfg env printed a REVEALUI_MCP_TOKEN= assignment"
else
  pass "rfg env does not print REVEALUI_MCP_TOKEN="
fi

if [[ "$out" == *"REVEALUI_MCP_URL="* ]]; then
  pass "rfg env still prints non-secret REVEALUI_MCP_URL"
else
  fail "rfg env should still print REVEALUI_MCP_URL"
fi

if [[ "$out" == *"REVEALUI_MCP_TOKEN_VAULT_PATH="* ]]; then
  pass "rfg env still prints non-secret vault path"
else
  fail "rfg env should still print REVEALUI_MCP_TOKEN_VAULT_PATH"
fi

echo ""
echo "--- Pre-set token in the parent env must not leak ---"

export REVEALUI_MCP_TOKEN="$FAKE_TOKEN"
out2="$(bash "$RFG" env 2>"$TMP/err2")" && rc2=0 || rc2=$?
err2="$(cat "$TMP/err2")"
unset REVEALUI_MCP_TOKEN
if [ "$rc2" -eq 0 ] && [[ "$out2"$'\n'"$err2" != *"$FAKE_TOKEN"* ]]; then
  pass "pre-set REVEALUI_MCP_TOKEN is not printed"
else
  fail "pre-set token leaked or env failed (exit=$rc2)"
fi

echo ""
echo "--- Static: no token-print / no eval-the-token teaching ---"

if grep -nE "printf ['\"]export REVEALUI_MCP_TOKEN=|echo .*REVEALUI_MCP_TOKEN=" "$RFG"; then
  fail "rfg.sh still prints an export of REVEALUI_MCP_TOKEN"
else
  pass "rfg.sh has no printf/echo export of REVEALUI_MCP_TOKEN"
fi

if grep -nE 'eval "\$\(rfg(\.sh)? env\)"|eval "\$\("\$HOME/.*/rfg\.sh" env\)"' \
  "$DOCS" "$ROOT/README.md" "$RFG" "$SMOKE" "$MINT" 2>/dev/null; then
  fail "tracked files still teach or eval rfg env for the token"
else
  pass "docs and helpers do not eval rfg env"
fi

if grep -q '_revealui_mcp_env_load' "$SMOKE"; then
  pass "smoke loads MCP env in-process via revealui-mcp-env.sh"
else
  fail "smoke no longer calls _revealui_mcp_env_load"
fi

if grep -q 'Never prints the token' "$MINT"; then
  pass "mint still advertises never-print"
else
  fail "mint lost the never-print contract"
fi

if grep -q 'never prints secrets' "$SMOKE"; then
  pass "smoke still advertises never-print"
else
  fail "smoke lost the never-print contract"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
