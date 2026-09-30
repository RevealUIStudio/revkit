#!/usr/bin/env bash
# test-fleet-root.sh — pin / infer / explicit env. Never $HOME as a code root.
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

unset REVEALFLEET_ROOT REVFLEET_ROOT REVEALUI_ROOT
export HOME="$TMP/evil"
mkdir -p "$HOME/revealfleet/revkit/shell/lib"
got="$(rfg_resolve_fleet_root)" && true || got="UNRESOLVED"
if [ "$got" = "$HOME/revealfleet" ]; then
  fail "HOME hijack must not become fleet root (got $got)"
else
  pass "HOME hijack does not win (got $got)"
fi
export HOME="$TMP/home"

mkdir -p "$TMP/fakefleet/revkit/shell/lib"
cp "$ROOT/shell/lib/fleet-root.sh" "$TMP/fakefleet/revkit/shell/lib/fleet-root.sh"
got="$(rfg_infer_fleet_from_path "$TMP/fakefleet/revkit")"
if [ "$got" = "$TMP/fakefleet" ]; then
  pass "infer from revkit checkout → parent fleet"
else
  fail "infer checkout: got $got"
fi
mkdir -p "$TMP/wtfleet/.wt/label/shell/lib"
got="$(rfg_infer_fleet_from_path "$TMP/wtfleet/.wt/label")"
if [ "$got" = "$TMP/wtfleet" ]; then
  pass "infer from .wt worktree → fleet"
else
  fail "infer worktree: got $got"
fi

mkdir -p "$TMP/pfx/lib/revkit"
cp "$ROOT/shell/lib/fleet-root.sh" "$TMP/pfx/lib/revkit/fleet-root.sh"
printf 'REVEALFLEET_ROOT=%s\n' "$TMP/pinned-fleet" >"$TMP/pfx/lib/revkit/pin.env"
pin_got="$(
  unset REVEALFLEET_ROOT REVFLEET_ROOT REVEALUI_ROOT
  # shellcheck disable=SC1091
  . "$TMP/pfx/lib/revkit/fleet-root.sh"
  rfg_resolve_fleet_root
)"
if [ "$pin_got" = "$TMP/pinned-fleet" ]; then
  pass "matched-prefix pin.env wins when not in-tree"
else
  fail "pin.env: got $pin_got"
fi
# Re-source the in-tree lib after the pin subshell.
# shellcheck disable=SC1091
. "$ROOT/shell/lib/fleet-root.sh"

export REVEALFLEET_ROOT="$TMP/explicit"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$TMP/explicit" ]; then
  pass "REVEALFLEET_ROOT override wins"
else
  fail "override: got $got"
fi
unset REVEALFLEET_ROOT
export REVFLEET_ROOT="$TMP/alias"
got="$(rfg_resolve_fleet_root)" && true || got=""
if [ "$got" = "$TMP/alias" ]; then
  fail "old root alias must not win: got $got"
else
  pass "old root alias is ignored"
fi
export REVEALFLEET_ROOT="$TMP/canonical"
export REVFLEET_ROOT="$TMP/alias"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$TMP/canonical" ]; then
  pass "REVEALFLEET_ROOT is the only env root"
else
  fail "explicit root: got $got"
fi
unset REVEALFLEET_ROOT
export REVEALFLEET_ROOT="$TMP/fleet"

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
export REVEALFLEET_ROOT="$TMP/fleet"
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

mkdir -p "$REVEALFLEET_ROOT/.planning"
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
rfg_resolve_launch_target "$TMP/fleet" ".planning" "$TMP/fleet" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ "$RFG_LAUNCH_TARGET" = "$REVEALFLEET_ROOT/.planning" ]; then
  pass "dotted checkout is a named repo"
else
  fail "dotted checkout: rc=$rc target=$RFG_LAUNCH_TARGET"
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

# Legacy ~/revfleet is fail-closed (exit 78). Child process so a ban cannot
# signal this test runner.
expect_banned() {
  local desc="$1"
  shift
  local out err rc
  rc=0
  out="$(
    bash --noprofile --norc -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      . "$1"
      shift
      "$@"
    ' bash "$ROOT/shell/lib/fleet-root.sh" "$@" 2>"$TMP/ban.err"
  )" || rc=$?
  err="$(cat "$TMP/ban.err" 2>/dev/null || true)"
  if [ "$rc" -eq 0 ]; then
    fail "$desc (expected die, out=$out err=$err)"
    return
  fi
  if [ -n "$out" ]; then
    fail "$desc (stdout leaked: $out)"
    return
  fi
  case "$err" in
    *"REVEALFLEET_ROOT=~/revealfleet"*) pass "$desc" ;;
    *) fail "$desc (missing REVEALFLEET_ROOT=~/revealfleet hint: $err)" ;;
  esac
}

unset RFG_WT_ROOT REVEALUI_ROOT
export HOME="$TMP/home"
mkdir -p "$HOME/revfleet/.wt/label" "$HOME/revealfleet/.wt/label" "$TMP/opt/revfleet/.wt" "$TMP/opt/revealfleet"

export REVEALFLEET_ROOT="$HOME/revfleet"
expect_banned "HOME/revfleet fleet root dies" rfg_resolve_fleet_root
expect_banned "HOME/revfleet wt root dies" rfg_wt_root

export REVEALFLEET_ROOT="$TMP/opt/revfleet"
expect_banned "*/revfleet fleet root dies" rfg_resolve_fleet_root

tilde_prefix="$(printf '\176')"
export REVEALFLEET_ROOT="${tilde_prefix}/revfleet"
expect_banned "tilde ~/revfleet fleet root dies" rfg_resolve_fleet_root

unset REVEALFLEET_ROOT
export RFG_WT_ROOT="$HOME/revfleet/.wt"
expect_banned "RFG_WT_ROOT under HOME/revfleet dies" rfg_wt_root
export RFG_WT_ROOT="$TMP/opt/revfleet/.wt"
expect_banned "RFG_WT_ROOT under */revfleet dies" rfg_wt_root
unset RFG_WT_ROOT

expect_banned "infer from legacy .wt dies" rfg_infer_fleet_from_path "$HOME/revfleet/.wt/label"

mkdir -p "$HOME/revfleet"
ln -sfn "$HOME/revfleet" "$TMP/via-legacy"
export REVEALFLEET_ROOT="$TMP/via-legacy"
expect_banned "symlink to legacy fleet root dies" rfg_resolve_fleet_root
unset REVEALFLEET_ROOT

rc=0
out="$(
  REVEALFLEET_ROOT="$HOME/revfleet" bash --noprofile --norc -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    got="$(rfg_resolve_fleet_root)" || true
    printf "SWALLOWED:%s\n" "$got"
  ' bash "$ROOT/shell/lib/fleet-root.sh" 2>"$TMP/ban.err"
)" || rc=$?
err="$(cat "$TMP/ban.err" 2>/dev/null || true)"
if [ "$rc" -eq 0 ] || printf '%s' "$out" | grep -q 'SWALLOWED'; then
  fail "swallowed resolve must still die (rc=$rc out=$out err=$err)"
else
  case "$err" in
    *"REVEALFLEET_ROOT=~/revealfleet"*) pass "command substitution cannot swallow the ban" ;;
    *) fail "swallow die missing hint (rc=$rc err=$err)" ;;
  esac
fi

export REVEALFLEET_ROOT="$HOME/revealfleet"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$HOME/revealfleet" ]; then
  pass "revealfleet segment is allowed"
else
  fail "revealfleet segment: got $got"
fi
export REVEALFLEET_ROOT="$TMP/opt/revfleet-backup"
got="$(rfg_resolve_fleet_root)"
if [ "$got" = "$TMP/opt/revfleet-backup" ]; then
  pass "revfleet-backup segment is allowed"
else
  fail "revfleet-backup: got $got"
fi
unset RFG_WT_ROOT
export REVEALFLEET_ROOT="$HOME/revealfleet"
got="$(rfg_wt_root)"
if [ "$got" = "$HOME/revealfleet/.wt" ]; then
  pass "wt root under revealfleet is allowed"
else
  fail "revealfleet wt: got $got"
fi
got="$(rfg_infer_fleet_from_path "$HOME/revealfleet/.wt/label")"
if [ "$got" = "$HOME/revealfleet" ]; then
  pass "infer from revealfleet .wt is allowed"
else
  fail "infer revealfleet wt: got $got"
fi

alias_hits="$(grep -n 'REVFLEET_ROOT' \
  "$ROOT/shell/shellrc.d/"*.sh \
  "$ROOT/shell/modes/vibe/aliases.sh" \
  "$ROOT/shell/lib/fleet-root.sh" \
  "$ROOT/shell/bin/rfg.sh" \
  "$ROOT/shell/bin/rfc.sh" \
  "$ROOT/bootstrap.sh" || true)"
if [ -n "$alias_hits" ]; then
  fail "REVFLEET_ROOT still accepted: $alias_hits"
else
  pass "REVFLEET_ROOT alias is gone from shell rc, vibe, launchers, bootstrap"
fi

# Navigation uses the same canonical configuration contract as the root resolver.
canonical_root="$TMP/canonical-root"
planning_rc=0
planning_got="$(
  export REVEALFLEET_ROOT="$canonical_root"
  unset REVEALFLEET_PLANNING
  export REVFLEET_PLANNING="$TMP/obsolete-planning"
  . "$ROOT/shell/shellrc.d/10-aliases.sh"
  __rv_planning_root 2>/dev/null
)" || planning_rc=$?
if [ "$planning_rc" -eq 1 ] && [ -z "$planning_got" ]; then
  pass "unset planning does not infer a personal folder or read the obsolete setting"
else
  fail "planning fallback: got $planning_got"
fi
planning_got="$(
  export REVEALFLEET_ROOT="$TMP/canonical-root"
  export REVEALFLEET_PLANNING="$TMP/custom planning"
  . "$ROOT/shell/shellrc.d/10-aliases.sh"
  __rv_planning_root
)"
if [ "$planning_got" = "$TMP/custom planning" ]; then
  pass "canonical planning setting accepts any absolute folder name, including spaces"
else
  fail "planning setting: got $planning_got"
fi

planning_rc=0
planning_got="$(REVEALFLEET_PLANNING=relative/path __rv_planning_root 2>/dev/null)" || planning_rc=$?
if [ "$planning_rc" -eq 1 ] && [ -z "$planning_got" ]; then
  pass "relative planning configuration is rejected"
else
  fail "relative planning configuration: rc=$planning_rc got=$planning_got"
fi

planning="$TMP/custom planning"
mkdir -p "$planning/scripts" "$planning/revcon-profiles"
touch "$planning/scripts/fleet-sync-integration.js"
sync_got="$(
  export REVEALFLEET_PLANNING="$planning"
  . "$ROOT/shell/shellrc.d/10-aliases.sh"
  node() { printf '%s\n' "$@"; }
  sync-test --status
)"
if [ "$sync_got" = "$(printf '%s\n' "$planning/scripts/fleet-sync-integration.js" --status revealui)" ]; then
  pass "sync-test uses the configured planning checkout"
else
  fail "configured sync-test: $sync_got"
fi
printf 'export PLANNING_ACTIVATED=yes\n' > "$planning/revcon-profiles/activate.sh"
activation="$(
  export REVEALFLEET_PLANNING="$planning"
  . "$ROOT/shell/shellrc.d/70-revcon-personal.sh"
  printf '%s' "${PLANNING_ACTIVATED:-}"
)"
if [ "$activation" = yes ]; then
  pass "private profile activation uses the configured planning checkout"
else
  fail "configured activation: $activation"
fi

mkdir -p "$TMP/isolated-bin"
for launcher in rfg rfc; do
  cp "$ROOT/shell/bin/$launcher.sh" "$TMP/isolated-bin/$launcher"
  launcher_rc=0
  launcher_out="$(
    unset REVEALUI_ROOT
    bash "$TMP/isolated-bin/$launcher" env 2>&1
  )" || launcher_rc=$?
  if [ "$launcher_rc" -eq 1 ] && [[ "$launcher_out" == *"fleet-root.sh is missing"* ]]; then
    pass "$launcher requires the shared root resolver"
  else
    fail "$launcher used a parallel resolver: rc=$launcher_rc output=$launcher_out"
  fi
done

echo "--- $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
