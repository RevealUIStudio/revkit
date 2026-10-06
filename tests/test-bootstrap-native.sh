#!/usr/bin/env bash
# test-bootstrap-native.sh
# A default bootstrap control-layer run must not write ~/.claude and must not
# run the claude CLI. The opt-in path projects ~/.claude from ~/.revealui.
# Pre-existing user files without a generated-by-revkit marker are kept.
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
    REVKIT_LINK_EDITORS="${REVKIT_LINK_EDITORS:-}" \
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
unset REVKIT_LINK_EDITORS || true
out="$(run_boot "$LINK/home")"
rc="${out%%$'\n'*}"
editors="$(grep -o 'editor [^ ]*' "$LINK_LOG" | awk '{print $2}' | tr '\n' ' ')"
first="${editors%% *}"
got="$(printf '%s' "$editors" | tr -s ' ' | sed 's/ $//')"
if [ "$rc" = "0" ] && [ "$got" = "revealui revealui" ] && [ ! -e "$LINK/home/.claude" ]; then
  pass "default revcon link uses revealui only and does not write ~/.claude"
else
  fail "default link editors rc=$rc editors='$editors'"
fi
: > "$LINK_LOG"
export REVKIT_LINK_EDITORS="revealui,cursor"
out="$(run_boot "$LINK/home")"
rc="${out%%$'\n'*}"
editors="$(grep -o 'editor [^ ]*' "$LINK_LOG" | awk '{print $2}' | tr '\n' ' ')"
got="$(printf '%s' "$editors" | tr -s ' ' | sed 's/ $//')"
if [ "$rc" = "0" ] && [ "$got" = "revealui cursor revealui cursor" ]; then
  pass "REVKIT_LINK_EDITORS adds only the requested editor once per repo"
else
  fail "requested editors rc=$rc editors='$editors'"
fi
unset REVKIT_LINK_EDITORS || true
unset REVEALFLEET_ROOT

# --- pre-existing user files are not destroyed ---
plant_user_files() {
  local home="$1"
  mkdir -p \
    "$home/.revealui/hooks" \
    "$home/.revealui/adapters/grok/hooks" \
    "$home/.revealui/adapters/claude/hooks" \
    "$home/.grok/hooks" \
    "$home/.claude/hooks"
  printf 'USER native scanner\n' > "$home/.revealui/hooks/m4-sudoers-fs-scanner.js"
  printf 'USER native session\n' > "$home/.revealui/hooks/session-start.js"
  printf 'USER native grok hook\n' > "$home/.revealui/adapters/grok/hooks/m4-sudoers-fs-scan.json"
  printf 'USER native grok config\n' > "$home/.revealui/adapters/grok/config.toml"
  printf 'USER native claude md\n' > "$home/.revealui/adapters/claude/CLAUDE.md"
  printf 'USER native claude hook\n' > "$home/.revealui/adapters/claude/hooks/m4-sudoers-fs-scan.json"
  printf 'USER grok hook\n' > "$home/.grok/hooks/m4-sudoers-fs-scan.json"
  printf 'owner = "user-keep"\n' > "$home/.grok/config.toml"
  printf 'USER claude md\n' > "$home/.claude/CLAUDE.md"
  printf 'USER claude hook\n' > "$home/.claude/hooks/m4-sudoers-fs-scan.json"
  printf 'KEEP revealui\n' > "$home/.revealui/KEEP.txt"
  printf 'KEEP grok\n' > "$home/.grok/KEEP.txt"
  printf 'KEEP claude\n' > "$home/.claude/KEEP.txt"
}

list_baks() {
  find "$1" -name '*.revkit-bak-*' -print | sort
}

exact_backup() {
  local path="$1"
  local needle="$2"
  local matches=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$f" ] && [ "$(cat "$f")" = "$needle" ]; then
      matches=$((matches + 1))
    fi
  done < <(find "$(dirname "$path")" -maxdepth 1 -name "$(basename "$path").revkit-bak-*" -type f -print)
  [ "$matches" -eq 1 ]
}

bak_name_ok() {
  local path="$1"
  local base
  base="$(find "$(dirname "$path")" -maxdepth 1 -name "$(basename "$path").revkit-bak-*" -printf '%f\n')"
  [[ "$base" =~ ^$(basename "$path")\.revkit-bak-[0-9]{14}(-[0-9]+)?$ ]]
}

live_is_projection() {
  local path="$1"
  local needle="$2"
  [ -f "$path" ] && grep -q -F 'generated-by-revkit' "$path" && ! grep -q -F "$needle" "$path"
}

keep_untouched() {
  local home="$1"
  [ "$(cat "$home/.revealui/KEEP.txt")" = "KEEP revealui" ] \
    && [ "$(cat "$home/.grok/KEEP.txt")" = "KEEP grok" ] \
    && [ "$(cat "$home/.claude/KEEP.txt")" = "KEEP claude" ] \
    && [ -z "$(find "$home" -name 'KEEP.txt.revkit-bak-*' -print)" ]
}

PRESERVE="$(new_home)"
export CLAUDE_LOG="$PRESERVE/claude.log"
export SUDO_LOG="$PRESERVE/sudo.log"
export BIN="$PRESERVE/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=control
unset REVEALFLEET_ROOT || true
unset REVKIT_LINK_EDITORS || true
plant_user_files "$PRESERVE/home"
out="$(run_boot "$PRESERVE/home")"
rc="${out%%$'\n'*}"
body="${out#*$'\n'}"
if [ "$rc" = "0" ] \
  && exact_backup "$PRESERVE/home/.revealui/hooks/m4-sudoers-fs-scanner.js" "USER native scanner" \
  && exact_backup "$PRESERVE/home/.revealui/hooks/session-start.js" "USER native session" \
  && exact_backup "$PRESERVE/home/.revealui/adapters/grok/hooks/m4-sudoers-fs-scan.json" "USER native grok hook" \
  && exact_backup "$PRESERVE/home/.revealui/adapters/grok/config.toml" "USER native grok config" \
  && exact_backup "$PRESERVE/home/.revealui/adapters/claude/CLAUDE.md" "USER native claude md" \
  && exact_backup "$PRESERVE/home/.revealui/adapters/claude/hooks/m4-sudoers-fs-scan.json" "USER native claude hook" \
  && exact_backup "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json" "USER grok hook" \
  && bak_name_ok "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json" \
  && live_is_projection "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json" "USER grok hook" \
  && live_is_projection "$PRESERVE/home/.revealui/hooks/m4-sudoers-fs-scanner.js" "USER native scanner" \
  && [ "$(cat "$PRESERVE/home/.claude/CLAUDE.md")" = "USER claude md" ] \
  && [ "$(cat "$PRESERVE/home/.claude/hooks/m4-sudoers-fs-scan.json")" = "USER claude hook" ] \
  && [ -z "$(find "$PRESERVE/home/.claude" -name '*.revkit-bak-*' -print)" ] \
  && grep -q 'owner = "user-keep"' "$PRESERVE/home/.grok/config.toml" \
  && grep -q 'hooks = false' "$PRESERVE/home/.grok/config.toml" \
  && keep_untouched "$PRESERVE/home" \
  && printf '%s\n' "$body" | grep -q 'Moved it to'; then
  pass "default run backs up unmarked native and grok files and leaves claude user files"
else
  fail "default preserve rc=$rc body=$body"
fi
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
  "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json" >/dev/null; then
  pass "backed-up grok hook is replaced by valid JSON"
else
  fail "projected grok hook is not valid JSON"
fi
baks="$(list_baks "$PRESERVE/home")"
out="$(run_boot "$PRESERVE/home")"
rc="${out%%$'\n'*}"
if [ "$rc" = "0" ] && [ "$(list_baks "$PRESERVE/home")" = "$baks" ] \
  && [ "$(cat "$PRESERVE/home/.claude/CLAUDE.md")" = "USER claude md" ]; then
  pass "second default run does not create another backup"
else
  fail "default re-run was not idempotent rc=$rc"
fi
printf '\nSTALE\n' >> "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json"
out="$(run_boot "$PRESERVE/home")"
rc="${out%%$'\n'*}"
if [ "$rc" = "0" ] && ! grep -q 'STALE' "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json" \
  && [ "$(list_baks "$PRESERVE/home")" = "$baks" ] \
  && grep -q -F 'generated-by-revkit' "$PRESERVE/home/.grok/hooks/m4-sudoers-fs-scan.json"; then
  pass "a marked projection is replaced in place without a new backup"
else
  fail "marked file was not replaced in place"
fi

PRESERVE_OPT="$(new_home)"
export CLAUDE_LOG="$PRESERVE_OPT/claude.log"
export SUDO_LOG="$PRESERVE_OPT/sudo.log"
export BIN="$PRESERVE_OPT/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=control
unset REVEALFLEET_ROOT || true
plant_user_files "$PRESERVE_OPT/home"
out="$(run_boot "$PRESERVE_OPT/home" --claude-adapter)"
rc="${out%%$'\n'*}"
if [ "$rc" = "0" ] && [ ! -s "$CLAUDE_LOG" ] \
  && exact_backup "$PRESERVE_OPT/home/.claude/CLAUDE.md" "USER claude md" \
  && exact_backup "$PRESERVE_OPT/home/.claude/hooks/m4-sudoers-fs-scan.json" "USER claude hook" \
  && exact_backup "$PRESERVE_OPT/home/.grok/hooks/m4-sudoers-fs-scan.json" "USER grok hook" \
  && exact_backup "$PRESERVE_OPT/home/.revealui/hooks/m4-sudoers-fs-scanner.js" "USER native scanner" \
  && exact_backup "$PRESERVE_OPT/home/.revealui/adapters/claude/CLAUDE.md" "USER native claude md" \
  && live_is_projection "$PRESERVE_OPT/home/.claude/CLAUDE.md" "USER claude md" \
  && live_is_projection "$PRESERVE_OPT/home/.claude/hooks/m4-sudoers-fs-scan.json" "USER claude hook" \
  && grep -q '.revealui' "$PRESERVE_OPT/home/.claude/CLAUDE.md" \
  && keep_untouched "$PRESERVE_OPT/home"; then
  pass "claude adapter backs up unmarked files in revealui, claude, and grok homes"
else
  fail "adapter preserve rc=$rc"
fi
baks="$(list_baks "$PRESERVE_OPT/home")"
out="$(run_boot "$PRESERVE_OPT/home" --claude-adapter)"
rc="${out%%$'\n'*}"
if [ "$rc" = "0" ] && [ "$(list_baks "$PRESERVE_OPT/home")" = "$baks" ] \
  && exact_backup "$PRESERVE_OPT/home/.claude/CLAUDE.md" "USER claude md" \
  && [ ! -s "$CLAUDE_LOG" ]; then
  pass "second claude-adapter run does not create another backup"
else
  fail "adapter re-run was not idempotent rc=$rc"
fi

# ~/.revealui that is a revkit checkout must not gain untracked adapters or hooks.
CHECKOUT="$(new_home)"
export CLAUDE_LOG="$CHECKOUT/claude.log"
export SUDO_LOG="$CHECKOUT/sudo.log"
export BIN="$CHECKOUT/bin"
: > "$CLAUDE_LOG"
: > "$SUDO_LOG"
export REVKIT_CLAUDE_ADAPTER=0
export REVKIT_BOOTSTRAP_ONLY=control
unset REVEALFLEET_ROOT || true
native="$CHECKOUT/home/.revealui"
mkdir -p "$native/shell/lib" "$CHECKOUT/home/.grok/hooks"
printf '#!/bin/bash\n' > "$native/bootstrap.sh"
printf '# stub\n' > "$native/shell/lib/native-home.sh"
printf 'USER grok hook\n' > "$CHECKOUT/home/.grok/hooks/m4-sudoers-fs-scan.json"
git -C "$native" init -q
git -C "$native" -c user.email=tester@example.com -c user.name=tester -c commit.gpgsign=false add -A
git -C "$native" -c user.email=tester@example.com -c user.name=tester -c commit.gpgsign=false commit -q -m 'init'
out="$(run_boot "$CHECKOUT/home")"
rc="${out%%$'\n'*}"
body="${out#*$'\n'}"
if [ "$rc" = "0" ] \
  && [ -z "$(git -C "$native" status --porcelain)" ] \
  && [ ! -e "$native/adapters" ] && [ ! -e "$native/hooks" ] \
  && printf '%s\n' "$body" | grep -q 'is a revkit checkout' \
  && exact_backup "$CHECKOUT/home/.grok/hooks/m4-sudoers-fs-scan.json" "USER grok hook" \
  && live_is_projection "$CHECKOUT/home/.grok/hooks/m4-sudoers-fs-scan.json" "USER grok hook"; then
  pass "a revkit checkout at ~/.revealui is left clean and grok still projects"
else
  fail "checkout case rc=$rc status=$(git -C "$native" status --porcelain) body=$body"
fi
out="$(run_boot "$CHECKOUT/home")"
rc="${out%%$'\n'*}"
if [ "$rc" = "0" ] && [ -z "$(git -C "$native" status --porcelain)" ]; then
  pass "second run still does not dirty a revkit checkout"
else
  fail "checkout re-run dirty rc=$rc status=$(git -C "$native" status --porcelain)"
fi

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

rm -rf "$BASE" "$OPT" "$DRY" "$LINK" "$FIX" "$PRESERVE" "$PRESERVE_OPT" "$CHECKOUT"
unset CLAUDE_LOG SUDO_LOG BIN LINK_LOG REVKIT_BOOTSTRAP_ONLY REVKIT_CLAUDE_ADAPTER GROK_HOME || true

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
