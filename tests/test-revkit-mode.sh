#!/usr/bin/env bash
# test-revkit-mode.sh — mode resolution (managed→fleet) and vibe subset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/shell/lib/revkit-mode.sh"
BIN="$ROOT/shell/bin/revkit-mode.sh"
BOOTSTRAP="$ROOT/bootstrap.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    pass "$label"
  else
    fail "$label — got '$got' want '$want'"
  fi
}

echo "=== test-revkit-mode.sh ==="

if [ ! -f "$LIB" ]; then
  echo "FAIL: missing $LIB"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME/.config/revkit"
unset REVEALUI_MODE REVEALUI_SHELL_READY || true
export REVEALUI_ROOT="$ROOT"

resolve() {
  # shellcheck disable=SC1090
  env "$@" bash --noprofile --norc -c "
    REVEALUI_ROOT='$ROOT'
    . '$LIB'
    revkit_resolve_mode
  "
}

# --- resolution ---
got="$(resolve -u REVEALUI_MODE)"
assert_eq "unset env + no file defaults to fleet" "$got" "fleet"

got="$(resolve REVEALUI_MODE=managed)"
assert_eq "REVEALUI_MODE=managed maps to fleet" "$got" "fleet"

got="$(resolve REVEALUI_MODE=MANAGED)"
assert_eq "REVEALUI_MODE=MANAGED maps to fleet" "$got" "fleet"

got="$(resolve REVEALUI_MODE=vibe)"
assert_eq "REVEALUI_MODE=vibe stays vibe" "$got" "vibe"

got="$(resolve REVEALUI_MODE=bare)"
assert_eq "REVEALUI_MODE=bare stays bare" "$got" "bare"

got="$(resolve REVEALUI_MODE=fleet)"
assert_eq "REVEALUI_MODE=fleet stays fleet" "$got" "fleet"

got="$(resolve REVEALUI_MODE=stream 2>/dev/null)"
assert_eq "REVEALUI_MODE=stream is not a workflow mode (defaults fleet)" "$got" "fleet"

printf 'vibe\n' > "$HOME/.config/revkit/mode"
got="$(resolve -u REVEALUI_MODE)"
assert_eq "preference file vibe when env unset" "$got" "vibe"

printf 'managed\n' > "$HOME/.config/revkit/mode"
got="$(resolve -u REVEALUI_MODE)"
assert_eq "preference file managed maps to fleet" "$got" "fleet"

printf 'fleet\n' > "$HOME/.config/revkit/mode"
got="$(resolve REVEALUI_MODE=vibe)"
assert_eq "env vibe overrides preference fleet" "$got" "vibe"

printf 'not-a-mode\n' > "$HOME/.config/revkit/mode"
got="$(resolve -u REVEALUI_MODE 2>/dev/null)"
assert_eq "invalid preference defaults to fleet" "$got" "fleet"
rm -f "$HOME/.config/revkit/mode"

# --- fragment lists ---
# shellcheck disable=SC1090
bash --noprofile --norc -c "
  REVEALUI_ROOT='$ROOT'
  . '$LIB'
  revkit_mode_list_paths fleet
" >"$TMP/fleet.list"
bash --noprofile --norc -c "
  REVEALUI_ROOT='$ROOT'
  . '$LIB'
  revkit_mode_list_paths vibe
" >"$TMP/vibe.list"
fleet_n="$(wc -l < "$TMP/fleet.list" | tr -d ' ')"
vibe_n="$(wc -l < "$TMP/vibe.list" | tr -d ' ')"
fleet_paths="$(tr '\n' '|' < "$TMP/fleet.list")"
vibe_paths="$(tr '\n' '|' < "$TMP/vibe.list")"

if [ "${vibe_n:-0}" -gt 0 ]; then
  pass "vibe list is non-empty ($vibe_n fragments)"
else
  fail "vibe list is empty"
fi

if [ "${fleet_n:-0}" -gt "${vibe_n:-0}" ]; then
  pass "vibe is a proper subset of fleet ($vibe_n < $fleet_n)"
else
  fail "vibe ($vibe_n) should be smaller than fleet ($fleet_n)"
fi

shellrc_n="$(find "$ROOT/shell/shellrc.d" -name '*.sh' | wc -l | tr -d ' ')"
assert_eq "fleet list expands to all shellrc.d/*.sh" "$fleet_n" "$shellrc_n"

case "$vibe_paths" in
  *00-base.sh*) pass "vibe includes 00-base.sh" ;;
  *) fail "vibe missing 00-base.sh" ;;
esac
case "$vibe_paths" in
  *20-tools.sh*) pass "vibe includes 20-tools.sh" ;;
  *) fail "vibe missing 20-tools.sh" ;;
esac
case "$vibe_paths" in
  *modes/vibe/aliases.sh*) pass "vibe includes modes/vibe/aliases.sh" ;;
  *) fail "vibe missing modes/vibe/aliases.sh" ;;
esac
case "$vibe_paths" in
  *10-aliases.sh*) fail "vibe should not load 10-aliases.sh (fleet ceremony)" ;;
  *) pass "vibe omits 10-aliases.sh" ;;
esac
case "$vibe_paths" in
  *50-rfc.sh*) fail "vibe should not load 50-rfc.sh (claim completion)" ;;
  *) pass "vibe omits 50-rfc.sh" ;;
esac
case "$vibe_paths" in
  *55-rfg.sh*) fail "vibe should not load 55-rfg.sh" ;;
  *) pass "vibe omits 55-rfg.sh" ;;
esac
case "$fleet_paths" in
  *10-aliases.sh*|*50-rfc.sh*|*55-rfg.sh*) pass "fleet includes claim/worktree fragments" ;;
  *) fail "fleet missing expected ceremony fragments" ;;
esac

# --- activate vibe: banner + helpers, no fleet ceremony ---
act="$(mktemp "$TMP/act.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  export REVEALUI_ROOT='$ROOT'
  export REVEALUI_MODE=vibe
  unset REVEALUI_SHELL_READY
  . '$LIB'
  revkit_mode_activate
  printf 'MODE=%s\n' \"\$REVEALUI_MODE\"
  type create-revealui >/dev/null && echo HAS_CREATE=1 || echo HAS_CREATE=0
  type open-revealui >/dev/null && echo HAS_OPEN=1 || echo HAS_OPEN=0
  type revkit-mode >/dev/null && echo HAS_SWITCHER=1 || echo HAS_SWITCHER=0
  type tracker >/dev/null 2>&1 && echo HAS_TRACKER=1 || echo HAS_TRACKER=0
  type wb >/dev/null 2>&1 && echo HAS_WB=1 || echo HAS_WB=0
  type sync-test >/dev/null 2>&1 && echo HAS_SYNC=1 || echo HAS_SYNC=0
" >"$act" 2>"$act.err" || true

if grep -q 'RevKit: vibe' "$act"; then
  pass "vibe activate prints vibe banner"
else
  fail "vibe activate banner missing (stdout=$(tr '\n' ' ' < "$act"))"
fi
if grep -q 'product-first' "$act"; then
  pass "vibe activate prints product-first tip"
else
  fail "vibe tip missing"
fi
assert_eq "vibe activate exports REVEALUI_MODE=vibe" \
  "$(grep '^MODE=' "$act" | cut -d= -f2)" "vibe"
assert_eq "vibe defines create-revealui" \
  "$(grep '^HAS_CREATE=' "$act" | cut -d= -f2)" "1"
assert_eq "vibe defines open-revealui" \
  "$(grep '^HAS_OPEN=' "$act" | cut -d= -f2)" "1"
assert_eq "vibe defines revkit-mode" \
  "$(grep '^HAS_SWITCHER=' "$act" | cut -d= -f2)" "1"
assert_eq "vibe does not define tracker" \
  "$(grep '^HAS_TRACKER=' "$act" | cut -d= -f2)" "0"
assert_eq "vibe does not define wb" \
  "$(grep '^HAS_WB=' "$act" | cut -d= -f2)" "0"
assert_eq "vibe does not define sync-test" \
  "$(grep '^HAS_SYNC=' "$act" | cut -d= -f2)" "0"

# preference file (no env) also activates vibe
printf 'vibe\n' > "$HOME/.config/revkit/mode"
actp="$(mktemp "$TMP/actp.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  export REVEALUI_ROOT='$ROOT'
  unset REVEALUI_MODE REVEALUI_SHELL_READY
  . '$LIB'
  revkit_mode_activate
  printf 'MODE=%s\n' \"\$REVEALUI_MODE\"
" >"$actp" 2>/dev/null || true
if grep -q 'RevKit: vibe' "$actp" && grep -q '^MODE=vibe$' "$actp"; then
  pass "preference file vibe activates vibe when env unset"
else
  fail "preference-file vibe activate failed"
fi
rm -f "$HOME/.config/revkit/mode"

# managed env still activates fleet fragments
actf="$(mktemp "$TMP/actf.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  export REVEALUI_ROOT='$ROOT'
  export REVEALUI_MODE=managed
  unset REVEALUI_SHELL_READY
  . '$LIB'
  revkit_mode_activate
  printf 'MODE=%s\n' \"\$REVEALUI_MODE\"
  type tracker >/dev/null 2>&1 && echo HAS_TRACKER=1 || echo HAS_TRACKER=0
" >"$actf" 2>/dev/null || true

if grep -q 'RevKit: fleet' "$actf"; then
  pass "managed env activate prints fleet banner"
else
  fail "managed→fleet banner missing"
fi
assert_eq "managed activate exports fleet" \
  "$(grep '^MODE=' "$actf" | cut -d= -f2)" "fleet"
assert_eq "managed→fleet defines tracker" \
  "$(grep '^HAS_TRACKER=' "$actf" | cut -d= -f2)" "1"

# bare: no fragments, gray banner
actb="$(mktemp "$TMP/actb.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export REVEALUI_ROOT='$ROOT'
  export REVEALUI_MODE=bare
  unset REVEALUI_SHELL_READY
  . '$LIB'
  revkit_mode_activate
  printf 'MODE=%s\n' \"\$REVEALUI_MODE\"
  type create-revealui >/dev/null 2>&1 && echo HAS_CREATE=1 || echo HAS_CREATE=0
" >"$actb" 2>/dev/null || true
if grep -q 'RevKit: bare' "$actb"; then
  pass "bare activate prints bare banner"
else
  fail "bare banner missing"
fi
assert_eq "bare does not define create-revealui" \
  "$(grep '^HAS_CREATE=' "$actb" | cut -d= -f2)" "0"

# --- CLI helper ---
chmod +x "$BIN" 2>/dev/null || true
rm -f "$HOME/.config/revkit/mode"
unset STREAM_SAFE REVVAULT_STREAM_SAFE REVVAULT_ALLOW_PRINT RV_STREAM || true
out="$("$BIN")"
assert_eq "revkit-mode.sh prints mode: fleet by default" \
  "$(printf '%s\n' "$out" | sed -n '1p')" "mode: fleet"
assert_eq "revkit-mode.sh prints stream: off by default" \
  "$(printf '%s\n' "$out" | sed -n '2p')" "stream: off"

code=0
"$BIN" banana >/dev/null 2>"$TMP/err" || code=$?
if [ "$code" -ne 0 ]; then
  pass "revkit-mode.sh rejects unknown mode"
else
  fail "revkit-mode.sh accepted unknown mode"
fi

"$BIN" vibe >/dev/null
pref="$(tr -d '[:space:]' < "$HOME/.config/revkit/mode")"
assert_eq "revkit-mode.sh vibe writes preference" "$pref" "vibe"

"$BIN" managed >/dev/null
pref="$(tr -d '[:space:]' < "$HOME/.config/revkit/mode")"
assert_eq "revkit-mode.sh managed writes fleet" "$pref" "fleet"

# --- stream overlay is orthogonal ---
ov="$(mktemp "$TMP/ov.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  export REVEALUI_ROOT='$ROOT'
  export REVEALUI_MODE=vibe
  unset STREAM_SAFE REVVAULT_STREAM_SAFE REVVAULT_ALLOW_PRINT RV_STREAM
  . '$LIB'
  revkit_mode_apply_stream_safe >/dev/null
  printf '%s\n' \"\$(revkit_resolve_mode)\"
  printf '%s\n' \"\$(revkit_mode_stream_state)\"
  printf '%s\n' \"\${REVEALUI_MODE}\"
" >"$ov" 2>/dev/null
assert_eq "stream-safe keeps resolved mode vibe" "$(sed -n '1p' "$ov")" "vibe"
assert_eq "stream-safe sets overlay state" "$(sed -n '2p' "$ov")" "stream-safe"
assert_eq "stream-safe does not change REVEALUI_MODE" "$(sed -n '3p' "$ov")" "vibe"

ov2="$(mktemp "$TMP/ov2.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  export REVEALUI_ROOT='$ROOT'
  export REVEALUI_MODE=fleet
  unset STREAM_SAFE REVVAULT_STREAM_SAFE REVVAULT_ALLOW_PRINT
  . '$LIB'
  revkit_mode_apply_vault_private >/dev/null
  printf '%s\n' \"\$(revkit_resolve_mode)\"
  printf '%s\n' \"\$(revkit_mode_stream_state)\"
  printf '%s\n' \"\${REVEALUI_MODE}\"
" >"$ov2" 2>/dev/null
assert_eq "vault-private keeps resolved mode fleet" "$(sed -n '1p' "$ov2")" "fleet"
assert_eq "vault-private sets overlay state" "$(sed -n '2p' "$ov2")" "vault-private"
assert_eq "vault-private does not change REVEALUI_MODE" "$(sed -n '3p' "$ov2")" "fleet"

# CLI overlay must not rewrite ~/.config/revkit/mode
printf 'fleet\n' > "$HOME/.config/revkit/mode"
unset REVEALUI_MODE || true
"$BIN" stream-safe >/dev/null 2>&1 || true
pref="$(tr -d '[:space:]' < "$HOME/.config/revkit/mode")"
assert_eq "CLI stream-safe does not rewrite mode preference" "$pref" "fleet"

code=0
"$BIN" stream >/dev/null 2>"$TMP/err-stream" || code=$?
if [ "$code" -ne 0 ]; then
  pass "revkit-mode.sh stream (not stream-safe) is rejected"
else
  fail "revkit-mode.sh accepted stream as a workflow mode"
fi

# RV_STREAM=1 on activate: overlay on, mode unchanged
actr="$(mktemp "$TMP/actr.XXXXXX")"
bash --noprofile --norc -c "
  export HOME='$HOME'
  export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  export REVEALUI_ROOT='$ROOT'
  export REVEALUI_MODE=vibe
  export RV_STREAM=1
  unset REVEALUI_SHELL_READY STREAM_SAFE REVVAULT_STREAM_SAFE REVVAULT_ALLOW_PRINT
  . '$LIB'
  revkit_mode_activate
  printf 'MODE=%s\n' \"\$REVEALUI_MODE\"
  printf 'STATE=%s\n' \"\$(revkit_mode_stream_state)\"
" >"$actr" 2>/dev/null || true
assert_eq "RV_STREAM activate keeps vibe" "$(grep '^MODE=' "$actr" | cut -d= -f2)" "vibe"
assert_eq "RV_STREAM activate sets stream-safe overlay" "$(grep '^STATE=' "$actr" | cut -d= -f2)" "stream-safe"

if grep -q 'REVEALUI_MODE=stream' "$ROOT/docs/MASTER_SPEC.md" && grep -q 'There is no' "$ROOT/docs/MASTER_SPEC.md"; then
  pass "MASTER_SPEC documents no REVEALUI_MODE=stream"
else
  fail "MASTER_SPEC should say there is no REVEALUI_MODE=stream"
fi

# --- bootstrap hook pins ---
if grep -q 'revkit-mode.sh' "$BOOTSTRAP" && grep -q 'revkit_mode_activate' "$BOOTSTRAP"; then
  pass "bootstrap hook sources revkit-mode.sh and activates"
else
  fail "bootstrap hook missing revkit-mode activate"
fi
if grep -q 'REVEALUI_MODE="managed"' "$BOOTSTRAP"; then
  fail "bootstrap still hardcodes REVEALUI_MODE=managed"
else
  pass "bootstrap does not hardcode managed"
fi
if grep -q 'REVEALUI_SHELL_READY' "$BOOTSTRAP"; then
  pass "bootstrap uses REVEALUI_SHELL_READY session guard"
else
  fail "bootstrap missing REVEALUI_SHELL_READY guard"
fi
if grep -q 'revkit-mode.sh' "$BOOTSTRAP" && grep -q 'HELPERS_DIR/revkit-mode' "$BOOTSTRAP"; then
  pass "bootstrap installs unsuffixed revkit-mode"
else
  fail "bootstrap does not install unsuffixed revkit-mode"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
