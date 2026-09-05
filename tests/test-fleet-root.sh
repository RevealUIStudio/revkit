#!/usr/bin/env bash
# test-fleet-root.sh — default $HOME/revealfleet with $HOME/revfleet fallback.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/shell/lib/fleet-root.sh"

pass=0
fail=0
pass() { echo "  PASS  $*"; pass=$((pass + 1)); }
fail() { echo "  FAIL  $*"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

echo "=== test-fleet-root.sh ==="

unset REVFLEET_ROOT
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$HOME/revealfleet" ]; then
  pass "unset + neither dir → \$HOME/revealfleet"
else
  fail "expected \$HOME/revealfleet, got $got"
fi

mkdir -p "$HOME/revfleet"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$HOME/revfleet" ]; then
  pass "unset + only revfleet → fallback"
else
  fail "fallback: got $got"
fi

mkdir -p "$HOME/revealfleet"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$HOME/revealfleet" ]; then
  pass "unset + both dirs → revealfleet wins"
else
  fail "both dirs: got $got"
fi

export REVFLEET_ROOT="$TMP/explicit"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$TMP/explicit" ]; then
  pass "REVFLEET_ROOT override wins"
else
  fail "override: got $got"
fi

mkdir -p "$TMP/fleet/revealui"
if rfg_path_is_in_fleet "$TMP/fleet" "$TMP/fleet" && rfg_path_is_in_fleet "$TMP/fleet" "$TMP/fleet/revealui"; then
  pass "in-fleet matches root and child"
else
  fail "in-fleet root/child"
fi
if rfg_path_is_in_fleet "$TMP/fleet" "$TMP"; then
  fail "parent of fleet should not match"
else
  pass "parent of fleet is outside"
fi

echo "--- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
