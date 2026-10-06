#!/usr/bin/env bash
# test-bootstrap-native.sh
# A default bootstrap control-layer run must not write ~/.claude and must not
# run the claude CLI. The opt-in path projects ~/.claude from ~/.revealui.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT="$ROOT/bootstrap.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-bootstrap-native.sh ==="

if grep -q 'claude-config' "$BOOT" "$ROOT/shell/lib/native-home.sh"; then
  fail "installer still names a vendor config repo"
else
  pass "installer does not name a vendor config repo"
fi
if grep -q 'plugin marketplace' "$BOOT" "$ROOT/shell/lib/native-home.sh"; then
  fail "installer still runs the claude marketplace command"
else
  pass "installer does not run the claude marketplace command"
fi
if grep -q '.revealui/workboard.md' "$ROOT/shell/shellrc.d/10-aliases.sh" \
  && ! grep -q '.claude/workboard.md' "$ROOT/shell/shellrc.d/10-aliases.sh"; then
  pass "wb reads .revealui/workboard.md"
else
  fail "wb still treats a vendor workboard as the path"
fi
if grep -q '.revealui/workboard.md' "$ROOT/docs/agent-coordination.md" \
  && ! grep -q '.claude/workboard.md' "$ROOT/docs/agent-coordination.md" \
  && ! grep -q '.claude' "$ROOT/templates/hooks/session-start.js"; then
  pass "coordination doc and session-start use native paths"
else
  fail "coordination doc or session-start still teaches a vendor path"
fi
if ! grep -q 'Clone/wire' "$ROOT/docs/ONBOARDING.md" "$ROOT/docs/MASTER_SPEC.md"; then
  pass "onboarding and master spec no longer list the vendor clone as a step"
else
  fail "onboarding or master spec still lists the vendor clone step"
fi

new_home() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/home" "$dir/bin"
  cat > "$dir/bin/claude" << 'EOF'
#!/bin/sh
echo "$*" >> "${CLAUDE_LOG:?}"
exit 0
EOF
  cat > "$dir/bin/sudo" << 'EOF'
#!/bin/sh
echo "$*" >> "${SUDO_LOG:?}"
exit 99
EOF
  chmod +x "$dir/bin/claude" "$dir/bin/sudo"
  printf '%s\n' "$dir"
}

run_boot() {
  local home="$1"
  shift
  local log rc
  log="$(mktemp)"
  set +e
  HOME="$home" \
    CLAUDE_LOG="${CLAUDE_LOG:?}" \
    SUDO_LOG="${SUDO_LOG:?}" \
    PATH="${BIN:?}:$PATH" \
    REVEALFLEET_ROOT="${REVEALFLEET_ROOT:-}" \
    REVEALUI_ROOT="" \
    GROK_HOME="${GROK_HOME:-$home/.grok}" \
    REVKIT_CLAUDE_ADAPTER="${REVKIT_CLAUDE_ADAPTER:-0}" \
    REVKIT_BOOTSTRAP_ONLY="${REVKIT_BOOTSTRAP_ONLY:-}" \
    bash "$BOOT" "$@" >"$log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc"
  cat "$log"
}

# --- default control-layer run ---
BASE="$(new_home)"
export CLAUDE_LOG="$BASE/claude.log"
export SUDO_LOG="$BASE/sudo.log"
export BIN="$BASE/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
mkdir -p "$BASE/home/.claude"
printf 'marker\n' > "$BASE/home/.claude/marker"
unset REVEALFLEET_ROOT || true
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=control
out="$(run_boot "$BASE/home")"
rc="${out%%$'\n'*}"
body="${out#*$'\n'}"
if [ "$rc" = "0" ]; then
  pass "default control-layer run exits 0"
else
  fail "default control-layer run rc=$rc body=$body"
fi
if [ ! -s "$CLAUDE_LOG" ]; then
  pass "default run does not execute the claude CLI"
else
  fail "default run executed claude: $(cat "$CLAUDE_LOG")"
fi
if [ ! -s "$SUDO_LOG" ]; then
  pass "control-layer run does not call sudo"
else
  fail "control-layer run called sudo: $(cat "$SUDO_LOG")"
fi
if [ "$(find "$BASE/home/.claude" -type f -print)" = "$BASE/home/.claude/marker" ] \
  && [ "$(cat "$BASE/home/.claude/marker")" = "marker" ]; then
  pass "default run does not write ~/.claude"
else
  fail "default run wrote ~/.claude: $(find "$BASE/home/.claude" -type f -print)"
fi
if [ -f "$BASE/home/.revealui/hooks/m4-sudoers-fs-scanner.js" ] \
  && [ -f "$BASE/home/.revealui/hooks/session-start.js" ]; then
  pass "M-4 scanner and session-start install under ~/.revealui/hooks"
else
  fail "native hooks missing"
fi
if [ ! -f "$BASE/home/.claude/hooks/m4-sudoers-fs-scanner.js" ]; then
  pass "scanner is not copied into ~/.claude/hooks"
else
  fail "scanner was copied into the vendor home"
fi
cfg="$BASE/home/.grok/config.toml"
if [ -f "$cfg" ] \
  && grep -q 'hooks = false' "$cfg" \
  && grep -q 'mcps = false' "$cfg" \
  && grep -q 'sessions = false' "$cfg" \
  && grep -q 'skills = false' "$cfg"; then
  pass "default Grok config keeps compat.claude off"
else
  fail "Grok compat defaults missing: $(cat "$cfg" 2>/dev/null || echo absent)"
fi
hook="$BASE/home/.grok/hooks/m4-sudoers-fs-scan.json"
if [ -f "$hook" ] && grep -q '.revealui/hooks/m4-sudoers-fs-scanner.js' "$hook" \
  && ! grep -q '.claude/hooks/m4' "$hook"; then
  pass "Grok adapter hook points at the native scanner"
else
  fail "Grok adapter hook is missing or points at a vendor copy"
fi
if printf '%s\n' "$body" | grep -q 'Claude adapter: off'; then
  pass "default run reports the claude adapter off"
else
  fail "default run did not report the adapter off: $body"
fi

# idempotent second default run
out="$(run_boot "$BASE/home")"
rc="${out%%$'\n'*}"
if [ "$rc" = "0" ] && [ ! -s "$CLAUDE_LOG" ] \
  && [ "$(find "$BASE/home/.claude" -type f -print)" = "$BASE/home/.claude/marker" ]; then
  pass "second default run still does not write ~/.claude or run claude"
else
  fail "second default run drifted rc=$rc"
fi

# --- opt-in projection ---
OPT="$(new_home)"
export CLAUDE_LOG="$OPT/claude.log"
export SUDO_LOG="$OPT/sudo.log"
export BIN="$OPT/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=control
unset REVEALFLEET_ROOT || true
out="$(run_boot "$OPT/home" --claude-adapter)"
rc="${out%%$'\n'*}"
body="${out#*$'\n'}"
if [ "$rc" = "0" ]; then
  pass "opt-in control-layer run exits 0"
else
  fail "opt-in run rc=$rc body=$body"
fi
if [ ! -s "$CLAUDE_LOG" ]; then
  pass "opt-in path does not execute the claude CLI"
else
  fail "opt-in path executed claude: $(cat "$CLAUDE_LOG")"
fi
if [ -f "$OPT/home/.claude/CLAUDE.md" ] \
  && grep -q '.revealui' "$OPT/home/.claude/CLAUDE.md" \
  && ! grep -q 'claude-config' "$OPT/home/.claude/CLAUDE.md"; then
  pass "opt-in projects a pointer from the native home"
else
  fail "opt-in projection pointer missing"
fi
if [ -f "$OPT/home/.claude/hooks/m4-sudoers-fs-scan.json" ] \
  && grep -q '.revealui/hooks/m4-sudoers-fs-scanner.js' "$OPT/home/.claude/hooks/m4-sudoers-fs-scan.json" \
  && [ ! -f "$OPT/home/.claude/hooks/m4-sudoers-fs-scanner.js" ] \
  && [ ! -d "$OPT/home/.claude/.git" ]; then
  pass "opt-in attaches the native scanner and does not clone a repo"
else
  fail "opt-in did not attach a native projection"
fi
if [ -f "$OPT/home/.revealui/adapters/claude/CLAUDE.md" ] \
  && cmp -s "$OPT/home/.revealui/adapters/claude/CLAUDE.md" "$OPT/home/.claude/CLAUDE.md"; then
  pass "vendor projection matches the native adapter tree"
else
  fail "projection was not generated from the native tree"
fi

# --- dry-run writes nothing ---
DRY="$(new_home)"
export CLAUDE_LOG="$DRY/claude.log"
export SUDO_LOG="$DRY/sudo.log"
export BIN="$DRY/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=""
unset REVEALFLEET_ROOT || true
out="$(run_boot "$DRY/home" --dry-run)"
rc="${out%%$'\n'*}"
body="${out#*$'\n'}"
if [ "$rc" = "0" ] && [ ! -e "$DRY/home/.claude" ] && [ ! -e "$DRY/home/.revealui" ] \
  && [ ! -s "$CLAUDE_LOG" ] && ! printf '%s\n' "$body" | grep -q 'claude-config'; then
  pass "dry-run does not write ~/.claude or run claude"
else
  fail "dry-run rc=$rc claude=$(cat "$CLAUDE_LOG") body=$body"
fi

# --- native link before vendor projection ---
LINK="$(new_home)"
export CLAUDE_LOG="$LINK/claude.log"
export SUDO_LOG="$LINK/sudo.log"
export BIN="$LINK/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
export LINK_LOG="$LINK/link.log"
: > "$LINK_LOG"
mkdir -p "$LINK/fleet/revkit" "$LINK/fleet/revcon"
cat > "$LINK/fleet/revcon/link.sh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${LINK_LOG:?}"
exit 0
EOF
chmod +x "$LINK/fleet/revcon/link.sh"
export REVEALFLEET_ROOT="$LINK/fleet"
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=control
out="$(run_boot "$LINK/home")"
rc="${out%%$'\n'*}"
editors="$(grep -o 'editor [^ ]*' "$LINK_LOG" | awk '{print $2}' | tr '\n' ' ')"
first="${editors%% *}"
if [ "$rc" = "0" ] && [ "$first" = "revealui" ] && printf '%s\n' "$editors" | grep -q 'claude' \
  && [ ! -e "$LINK/home/.claude" ]; then
  pass "revcon links revealui before vendor editors and does not write ~/.claude"
else
  fail "link order rc=$rc editors='$editors'"
fi
unset REVEALFLEET_ROOT

# --- lockstep: native reference, vendor projection ---
if bash "$ROOT/scripts/verify-copy-lockstep.sh" --target "$ROOT" >/dev/null; then
  pass "repo lockstep accepts .revealui/content as the reference"
else
  fail "repo lockstep failed"
fi

FIX="$(mktemp -d)"
git -C "$FIX" init -q
mkdir -p "$FIX/.revealui/content/rules" "$FIX/.claude/rules"
printf 'native\n' > "$FIX/.revealui/content/rules/a.md"
printf 'native\n' > "$FIX/.claude/rules/a.md"
hash="$(sha256sum "$FIX/.revealui/content/rules/a.md" | awk '{print $1}')"
cat > "$FIX/.revealui/.revcon-manifest.json" << EOF
{
  "mode": "copy",
  "editor": "revealui",
  "profiles": ["revealfleet"],
  "files": {
    "content/rules/a.md": {
      "source": ".revealui/content/rules/a.md",
      "sha256": "$hash"
    }
  }
}
EOF
git -C "$FIX" add -A
if bash "$ROOT/scripts/verify-copy-lockstep.sh" --target "$FIX" --dot .claude >/dev/null; then
  pass "matching vendor projection passes lockstep"
else
  fail "matching projection should pass"
fi
printf 'drift\n' > "$FIX/.claude/rules/a.md"
if bash "$ROOT/scripts/verify-copy-lockstep.sh" --target "$FIX" --dot .claude >/dev/null 2>&1; then
  fail "drifted vendor projection should fail lockstep"
else
  pass "drifted vendor projection fails against .revealui/content"
fi

rm -rf "$BASE" "$OPT" "$DRY" "$LINK" "$FIX"
unset CLAUDE_LOG SUDO_LOG BIN LINK_LOG REVKIT_BOOTSTRAP_ONLY REVKIT_CLAUDE_ADAPTER GROK_HOME || true

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
