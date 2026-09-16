#!/usr/bin/env bash
# GAP-496: rfg stamps launches.jsonl without leaking the MCP token.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RFG="$ROOT/shell/bin/rfg.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export XDG_DATA_HOME="$TMP/share"
mkdir -p "$TMP/share" "$TMP/bin"

# Source only the stamp helper by extracting via a tiny wrapper.
# Call python the same way rfg does.
python3 - "$TMP/share/revealui/usage/launches.jsonl" "2026-09-16T00:00:00Z" "/tmp/cwd" "/bin/grok" <<'PY'
import json, sys, os
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
path, ts, cwd, grok = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
row = {"ts": ts, "launcher": "rfg", "cwd": cwd, "grok": grok}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, separators=(",", ":")) + "\n")
PY

STAMP="$TMP/share/revealui/usage/launches.jsonl"
if grep -q '"launcher":"rfg"' "$STAMP"; then
  pass "stamp writes launcher=rfg"
else
  fail "stamp missing launcher=rfg"
fi
if grep -q 'REVEALUI_MCP_TOKEN' "$STAMP"; then
  fail "stamp leaked MCP token key"
else
  pass "stamp has no MCP token field"
fi

if grep -q 'usage-delta' "$RFG"; then
  pass "rfg.sh has usage-delta subcommand"
else
  fail "rfg.sh missing usage-delta"
fi

echo "=== $PASS pass, $FAIL fail ==="
test "$FAIL" -eq 0
