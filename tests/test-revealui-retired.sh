#!/usr/bin/env bash
# test-revealui-retired.sh — GAP-351 retire shim (no tmux, points at rfg/rfc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$ROOT/shell/bin/revealui.sh"
BOOTSTRAP="$ROOT/bootstrap.sh"
SHELLRC="$ROOT/shell/shellrc.d/52-revealui.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-revealui-retired.sh ==="

if [ -x "$SHIM" ] || [ -f "$SHIM" ]; then
  pass "shim exists at shell/bin/revealui.sh"
else
  fail "missing shell/bin/revealui.sh"
fi

if grep -Eq 'tmux[[:space:]]+(new|attach|has-session|list-windows)' "$SHIM"; then
  fail "shim still invokes tmux session commands"
else
  pass "shim does not invoke tmux session commands"
fi

if grep -q 'HOME/projects' "$SHIM"; then
  fail "shim still references HOME/projects"
else
  pass "shim does not reference HOME/projects"
fi

ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT
code=0
bash "$SHIM" list >/dev/null 2>"$ERR" || code=$?
err="$(cat "$ERR")"

if [ "$code" = "2" ]; then
  pass "exit 2 on list"
else
  fail "expected exit 2, got $code"
fi

if echo "$err" | grep -q 'rfg' && echo "$err" | grep -q 'rfc'; then
  pass "stderr names rfg and rfc"
else
  fail "stderr must name rfg and rfc, got: $err"
fi

if echo "$err" | grep -qi multiplexer || echo "$err" | grep -qi retired; then
  pass "stderr says retired / no multiplexer"
else
  fail "stderr should say retired, got: $err"
fi

code=0
bash "$SHIM" >/dev/null 2>&1 || code=$?
if [ "$code" = "2" ]; then
  pass "exit 2 with no args"
else
  fail "expected exit 2 with no args, got $code"
fi

if grep -q 'GAP-351' "$BOOTSTRAP" && grep -q '.local/bin/revealui' "$BOOTSTRAP"; then
  pass "bootstrap overwrites ~/.local/bin/revealui"
else
  fail "bootstrap must install ~/.local/bin/revealui (GAP-351)"
fi

if [ -f "$SHELLRC" ] && grep -q 'revealui()' "$SHELLRC"; then
  pass "shellrc wrapper exists"
else
  fail "missing shell/shellrc.d/52-revealui.sh wrapper"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
