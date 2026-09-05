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

unset RFG_WT_ROOT
export REVFLEET_ROOT="$TMP/fleet"
got="$(rfg_wt_root)"
if [ "$got" = "$TMP/fleet/.wt" ]; then
  pass "wt root follows resolved fleet"
else
  fail "wt root: got $got"
fi
export RFG_WT_ROOT="$TMP/custom-wt"
got="$(rfg_wt_root)"
if [ "$got" = "$TMP/custom-wt" ]; then
  pass "RFG_WT_ROOT override wins"
else
  fail "wt override: got $got"
fi
unset RFG_WT_ROOT

mkdir -p "$TMP/fleet/.jv"
rfg_resolve_launch_target "$TMP/fleet" "" "$TMP/fleet" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ "$RFG_LAUNCH_TARGET" = "$TMP/fleet" ]; then
  pass "empty arg at fleet root → fleet root"
else
  fail "empty at root: rc=$rc target=$RFG_LAUNCH_TARGET"
fi
rfg_resolve_launch_target "$TMP/fleet" "." "$TMP/fleet/revealui" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ "$RFG_LAUNCH_TARGET" = "$TMP/fleet/revealui" ]; then
  pass ". in product → PWD (not fleet root)"
else
  fail ". in product: rc=$rc target=$RFG_LAUNCH_TARGET"
fi
rfg_resolve_launch_target "$TMP/fleet" ".jv" "$TMP/fleet" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ "$RFG_LAUNCH_TARGET" = "$TMP/fleet/.jv" ]; then
  pass "dotted checkout .jv is a named repo"
else
  fail ".jv: rc=$rc target=$RFG_LAUNCH_TARGET"
fi
rfg_resolve_launch_target "$TMP/fleet" ".." "$TMP/fleet" && rc=0 || rc=$?
if [ "$rc" -eq 1 ]; then
  pass ".. is rejected"
else
  fail ".. should be rc=1, got $rc target=$RFG_LAUNCH_TARGET"
fi
rfg_resolve_launch_target "$TMP/fleet" "../revealui" "$TMP/fleet" && rc=0 || rc=$?
if [ "$rc" -eq 1 ]; then
  pass "path with slash is rejected"
else
  fail "slash: rc=$rc target=$RFG_LAUNCH_TARGET"
fi
rfg_resolve_launch_target "$TMP/fleet" "revealui" "$TMP/fleet" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ "$RFG_LAUNCH_TARGET" = "$TMP/fleet/revealui" ]; then
  pass "named repo still resolves under fleet"
else
  fail "revealui: rc=$rc target=$RFG_LAUNCH_TARGET"
fi
rfg_resolve_launch_target "$TMP/fleet" "" "$TMP" && rc=0 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "outside fleet with no args → list-repos"
else
  fail "outside: rc=$rc"
fi

echo "--- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
