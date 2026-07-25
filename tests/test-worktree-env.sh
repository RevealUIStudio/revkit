#!/usr/bin/env bash
# test-worktree-env.sh — Rift-inspired ports + claims (RevKit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/shell/lib/worktree-env.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Ports are deterministic for a label
b1="$(rfg_port_base_for 'ves-fo-managed')"
b2="$(rfg_port_base_for 'ves-fo-managed')"
if [ "$b1" = "$b2" ] && [ "$b1" -ge 3000 ] && [ "$b1" -le 9999 ]; then
  pass "port base stable and in range ($b1)"
else
  fail "port base expected stable 3000-9999, got $b1 / $b2"
fi

# Different labels usually differ (not guaranteed but likely)
b3="$(rfg_port_base_for 'ves-fo-how-it-works')"
if [ "$b1" != "$b3" ]; then
  pass "distinct labels → distinct bases ($b1 vs $b3)"
else
  pass "distinct labels collided (rare hash collision ok) ($b1)"
fi

# Write env
TMP="$(mktemp -d)"
export REVEALUI_CLAIMS_DIR="$TMP/claims"
export REVEALUI_WT_ENV_DIR="$TMP/wtenv"
trap 'rm -rf "$TMP"' EXIT
wt="$TMP/wt-sample"
mkdir -p "$wt"
envf="$(rfg_write_worktree_env "$wt" 'wt-sample')"
if [ -f "$envf" ] && grep -q 'RFG_PORT_BASE=' "$envf" && grep -q 'API_PORT=' "$envf"; then
  pass "wrote .env.worktree with multi-service ports"
else
  fail "env file missing expected keys: $envf"
fi

# Claims: free → acquire → active → release
out="$(rfg_claim_check demo-repo 'marketing/ves-test' 2>&1 || true)"
if echo "$out" | grep -q free; then
  pass "claim check free"
else
  fail "expected free claim, got: $out"
fi

file="$(RFG_CLAIM_AGENT=test RFG_CLAIM_WORKTREE="$wt" rfg_claim_acquire demo-repo 'marketing/ves-test' 1)"
if [ -f "$file" ] && grep -q '"pid"' "$file"; then
  pass "claim acquire wrote $file"
else
  fail "claim acquire failed"
fi

if rfg_claim_check demo-repo 'marketing/ves-test' >/dev/null; then
  pass "claim check active while pid live"
else
  fail "claim should be active"
fi

# Second acquire without force should fail
if RFG_CLAIM_FORCE=0 rfg_claim_acquire demo-repo 'marketing/ves-test' 1 >/dev/null 2>&1; then
  fail "second acquire should fail without force"
else
  pass "second acquire blocked without force"
fi

rfg_claim_release demo-repo 'marketing/ves-test' >/dev/null
if rfg_claim_check demo-repo 'marketing/ves-test' >/dev/null 2>&1; then
  fail "claim still active after release"
else
  pass "claim free after release"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
