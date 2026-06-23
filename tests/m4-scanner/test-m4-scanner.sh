#!/usr/bin/env bash
# test-m4-scanner.sh — Smoke tests for revkit/shell/bin/m4-sudoers-fs-scanner.js
#
# Spec: internal fleet-security-hardening lane § M-4 (meta-durability-fixes)
#
# Each test sets up an isolated fixture tree in /tmp, invokes the scanner
# with M4_SUDOERS_DIR_OVERRIDE + M4_FS_OVERRIDE_HOME + M4_FS_OVERRIDE_SUDOLOG
# pointing at the fixtures, and asserts on:
#   - exit code (0 for clean, 2 for violation)
#   - stderr containing the expected violation marker
#
# Run:  bash revkit/tests/m4-scanner/test-m4-scanner.sh
# Or:   bash revkit/tests/m4-scanner/test-m4-scanner.sh --verbose
#
# All fixtures live under a per-run temp dir and are cleaned up on exit
# (trap EXIT). No system paths are touched.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCANNER="$REPO_ROOT/shell/bin/m4-sudoers-fs-scanner.js"

if [ ! -f "$SCANNER" ]; then
    echo "ERROR: scanner not found at $SCANNER" >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node not on PATH" >&2
    exit 1
fi

VERBOSE=0
if [ "${1:-}" = "--verbose" ]; then VERBOSE=1; fi

FIXTURES_ROOT="$(mktemp -d -t m4-scanner-tests.XXXXXX)"
trap 'rm -rf "$FIXTURES_ROOT"' EXIT

PASS=0
FAIL=0

# Each test reset: fresh sudoers dir + fresh home dir.
reset_fixtures() {
    local test_id="$1"
    SUDOERS="$FIXTURES_ROOT/$test_id/sudoers.d"
    HOME_FIXTURE="$FIXTURES_ROOT/$test_id/home"
    SUDOLOG_FIXTURE="$FIXTURES_ROOT/$test_id/sudo.log"
    mkdir -p "$SUDOERS" "$HOME_FIXTURE/.age-identity" "$HOME_FIXTURE/.ssh"
    # By default, set up CLEAN baseline. Each test mutates from there.
    cat > "$SUDOERS/00-defaults" <<'EOF'
# RevealUI defense-in-depth sudoers defaults.
# justification: tightens audit trail and friction profile after removing NOPASSWD: ALL.
Defaults    timestamp_timeout=10
Defaults    use_pty
Defaults    env_reset
Defaults    log_subcmds
Defaults    logfile=/var/log/sudo.log
Defaults    passwd_tries=3
EOF
    chmod 0440 "$SUDOERS/00-defaults"
    # Clean age identity.
    echo "test-age-identity" > "$HOME_FIXTURE/.age-identity/keys.txt"
    chmod 0600 "$HOME_FIXTURE/.age-identity/keys.txt"
    chmod 0700 "$HOME_FIXTURE/.age-identity"
}

run_scanner() {
    M4_SUDOERS_DIR_OVERRIDE="$SUDOERS" \
    M4_FS_OVERRIDE_HOME="$HOME_FIXTURE" \
    M4_FS_OVERRIDE_SUDOLOG="$SUDOLOG_FIXTURE" \
    node "$SCANNER" 2>"$FIXTURES_ROOT/last-stderr.txt"
    echo "$?"
}

assert_exit_code() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        [ "$VERBOSE" -eq 1 ] && echo "  PASS: $test_name (exit=$actual)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name — expected exit $expected, got $actual"
        echo "  --- stderr ---"
        sed 's/^/    /' "$FIXTURES_ROOT/last-stderr.txt"
        echo "  --- end stderr ---"
    fi
}

assert_stderr_contains() {
    local test_name="$1"
    local needle="$2"
    if grep -qF -- "$needle" "$FIXTURES_ROOT/last-stderr.txt"; then
        PASS=$((PASS + 1))
        [ "$VERBOSE" -eq 1 ] && echo "  PASS: $test_name (stderr contains \"$needle\")"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name — stderr did NOT contain \"$needle\""
        echo "  --- stderr ---"
        sed 's/^/    /' "$FIXTURES_ROOT/last-stderr.txt"
        echo "  --- end stderr ---"
    fi
}

assert_stderr_not_contains() {
    local test_name="$1"
    local needle="$2"
    if grep -qF -- "$needle" "$FIXTURES_ROOT/last-stderr.txt"; then
        FAIL=$((FAIL + 1))
        echo "  FAIL: $test_name — stderr unexpectedly contained \"$needle\""
    else
        PASS=$((PASS + 1))
        [ "$VERBOSE" -eq 1 ] && echo "  PASS: $test_name (stderr does NOT contain \"$needle\")"
    fi
}

# ============================================================================
# Test 1 — clean baseline (everything correct → exit 0, no findings)
# ============================================================================
echo "[1] clean baseline"
reset_fixtures "01-clean"
exit_code=$(run_scanner)
assert_exit_code "clean baseline" 0 "$exit_code"
assert_stderr_not_contains "clean baseline" "[M-4]"

# ============================================================================
# Test 2 — NOPASSWD: ALL is forbidden
# ============================================================================
echo "[2] NOPASSWD: ALL forbidden"
reset_fixtures "02-nopasswd-all"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: legacy entry that should be flagged
testuser ALL=(ALL) NOPASSWD: ALL
EOF
exit_code=$(run_scanner)
assert_exit_code "NOPASSWD: ALL exit code" 2 "$exit_code"
assert_stderr_contains "NOPASSWD: ALL marker" "NOPASSWD: ALL is forbidden"

# ============================================================================
# Test 3 — NOPASSWD to /usr/bin/mount (system-binary path) forbidden
# ============================================================================
echo "[3] NOPASSWD to system-binary path"
reset_fixtures "03-system-binary"
cat > "$SUDOERS/wsl-mount" <<'EOF'
# justification: legacy mount entry
testuser ALL=(root) NOPASSWD: /usr/bin/mount
EOF
exit_code=$(run_scanner)
assert_exit_code "system-binary path exit code" 2 "$exit_code"
assert_stderr_contains "system-binary marker" "system-binary path /usr/bin/mount"

# ============================================================================
# Test 4 — NOPASSWD with glob/wildcard in args forbidden
# ============================================================================
echo "[4] NOPASSWD with glob in args"
reset_fixtures "04-glob-arg"
cat > "$SUDOERS/wsl-mount" <<'EOF'
# justification: glob-arg entry
testuser ALL=(root) NOPASSWD: /usr/local/bin/mount-sandbox-drive.sh --mount-*
EOF
exit_code=$(run_scanner)
assert_exit_code "glob arg exit code" 2 "$exit_code"
assert_stderr_contains "glob arg marker" "glob/wildcard char"

# ============================================================================
# Test 5 — NOPASSWD to /usr/local/bin/<script> WITHOUT pinned arg
# ============================================================================
echo "[5] NOPASSWD to /usr/local/bin/script with no arg"
reset_fixtures "05-no-arg-pin"
cat > "$SUDOERS/wsl-mount" <<'EOF'
# justification: dangling-no-arg entry
testuser ALL=(root) NOPASSWD: /usr/local/bin/mount-sandbox-drive.sh
EOF
exit_code=$(run_scanner)
assert_exit_code "no-arg-pin exit code" 2 "$exit_code"
assert_stderr_contains "no-arg-pin marker" "without a pinned literal arg"

# ============================================================================
# Test 6 — NOPASSWD entry without `# justification:` comment forbidden
# ============================================================================
echo "[6] NOPASSWD entry without justification comment"
reset_fixtures "06-no-justification"
cat > "$SUDOERS/wsl-mount" <<'EOF'
# random comment that is not a justification
testuser ALL=(root) NOPASSWD: /usr/local/bin/mount-sandbox-drive.sh --mount-only
EOF
exit_code=$(run_scanner)
assert_exit_code "no-justification exit code" 2 "$exit_code"
assert_stderr_contains "no-justification marker" "has no \`# justification:"

# ============================================================================
# Test 7 — 00-defaults missing required keyword
# ============================================================================
echo "[7] 00-defaults missing required keyword"
reset_fixtures "07-defaults-missing-key"
# Overwrite the clean baseline 00-defaults with one missing log_subcmds.
# rm first: the baseline is mode 0440, which a non-root owner cannot truncate.
rm -f "$SUDOERS/00-defaults"
cat > "$SUDOERS/00-defaults" <<'EOF'
# RevealUI defense-in-depth sudoers defaults.
# justification: missing log_subcmds intentionally for this test
Defaults    timestamp_timeout=10
Defaults    use_pty
Defaults    env_reset
Defaults    logfile=/var/log/sudo.log
Defaults    passwd_tries=3
EOF
chmod 0440 "$SUDOERS/00-defaults"
exit_code=$(run_scanner)
assert_exit_code "defaults-missing exit code" 2 "$exit_code"
assert_stderr_contains "defaults-missing marker" "log_subcmds"

# ============================================================================
# Test 8 — 00-defaults file entirely absent
# ============================================================================
echo "[8] 00-defaults file absent"
reset_fixtures "08-defaults-absent"
rm "$SUDOERS/00-defaults"
exit_code=$(run_scanner)
assert_exit_code "defaults-absent exit code" 2 "$exit_code"
assert_stderr_contains "defaults-absent marker" "00-defaults is missing"

# ============================================================================
# Test 9 — age identity keys.txt has wrong mode (744 instead of 600)
# ============================================================================
echo "[9] age identity wrong mode"
reset_fixtures "09-age-key-mode"
chmod 0744 "$HOME_FIXTURE/.age-identity/keys.txt"
exit_code=$(run_scanner)
assert_exit_code "age-key-mode exit code" 2 "$exit_code"
assert_stderr_contains "age-key-mode marker" "must be mode 600"

# ============================================================================
# Test 10 — age identity directory has wrong mode (755 instead of 700)
# ============================================================================
echo "[10] age identity dir wrong mode"
reset_fixtures "10-age-dir-mode"
chmod 0755 "$HOME_FIXTURE/.age-identity"
exit_code=$(run_scanner)
assert_exit_code "age-dir-mode exit code" 2 "$exit_code"
assert_stderr_contains "age-dir-mode marker" "directory must be mode 700"

# ============================================================================
# Test 11 — SSH private key has wrong mode
# ============================================================================
echo "[11] SSH private key wrong mode"
reset_fixtures "11-ssh-key-mode"
echo "fake-key" > "$HOME_FIXTURE/.ssh/id_ed25519"
echo "fake-pub" > "$HOME_FIXTURE/.ssh/id_ed25519.pub"
chmod 0644 "$HOME_FIXTURE/.ssh/id_ed25519"
chmod 0644 "$HOME_FIXTURE/.ssh/id_ed25519.pub"
exit_code=$(run_scanner)
assert_exit_code "ssh-key-mode exit code" 2 "$exit_code"
assert_stderr_contains "ssh-key-mode marker" "id_ed25519"

# ============================================================================
# Test 12 — SSH .pub keys do NOT trigger violations even at 644
# ============================================================================
echo "[12] SSH .pub keys ignored"
reset_fixtures "12-ssh-pub-ignored"
echo "fake-key" > "$HOME_FIXTURE/.ssh/id_ed25519"
echo "fake-pub" > "$HOME_FIXTURE/.ssh/id_ed25519.pub"
chmod 0600 "$HOME_FIXTURE/.ssh/id_ed25519"
chmod 0644 "$HOME_FIXTURE/.ssh/id_ed25519.pub"
exit_code=$(run_scanner)
assert_exit_code "ssh-pub-ignored exit code" 0 "$exit_code"
assert_stderr_not_contains "ssh-pub-ignored marker" "id_ed25519.pub"

# ============================================================================
# Test 13 — pinned NOPASSWD entry WITH justification is allowed
# ============================================================================
echo "[13] correctly-pinned NOPASSWD entry"
reset_fixtures "13-clean-nopasswd"
cat > "$SUDOERS/wsl-mount" <<'EOF'
# RevealUI Sandbox USB auto-mount (kept per T0-3).
# justification: USB-insert trigger needs root; arg pinned to --mount-only literal.
testuser ALL=(root) NOPASSWD: /usr/local/bin/mount-sandbox-drive.sh --mount-only
EOF
exit_code=$(run_scanner)
assert_exit_code "clean-nopasswd exit code" 0 "$exit_code"
assert_stderr_not_contains "clean-nopasswd marker" "[M-4]"

# ============================================================================
# Test 14 — passage-store directory mode 750 triggers (looser than 700)
# ============================================================================
echo "[14] passage-store too permissive"
reset_fixtures "14-passage-store-loose"
mkdir -p "$HOME_FIXTURE/.revealui/passage-store"
chmod 0750 "$HOME_FIXTURE/.revealui/passage-store"
exit_code=$(run_scanner)
assert_exit_code "passage-store-loose exit code" 2 "$exit_code"
assert_stderr_contains "passage-store-loose marker" "passage-store"

# ============================================================================
# Test 15 — multiple violations are ALL reported (not just first)
# ============================================================================
echo "[15] multiple violations"
reset_fixtures "15-multiple"
chmod 0744 "$HOME_FIXTURE/.age-identity/keys.txt"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: legacy entry
testuser ALL=(ALL) NOPASSWD: ALL
EOF
exit_code=$(run_scanner)
assert_exit_code "multiple violations exit code" 2 "$exit_code"
assert_stderr_contains "multiple violations marker A" "NOPASSWD: ALL is forbidden"
assert_stderr_contains "multiple violations marker B" "must be mode 600"

# ============================================================================
# Test 16 — sudo audit log wrong mode (644 instead of 600)
# ============================================================================
echo "[16] sudo audit log wrong mode"
reset_fixtures "16-sudolog-mode"
echo "fake log" > "$SUDOLOG_FIXTURE"
chmod 0644 "$SUDOLOG_FIXTURE"
exit_code=$(run_scanner)
assert_exit_code "sudolog-mode exit code" 2 "$exit_code"
assert_stderr_contains "sudolog-mode marker" "sudo.log"

# ============================================================================
# Test 17 — joined tag form NOPASSWD:SETENV: must not hide ALL
# ============================================================================
echo "[17] joined SETENV tag + ALL"
reset_fixtures "17-joined-setenv-all"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — joined SETENV tag must not hide ALL
testuser ALL=(ALL) NOPASSWD:SETENV: ALL
EOF
exit_code=$(run_scanner)
assert_exit_code "joined SETENV+ALL exit code" 2 "$exit_code"
assert_stderr_contains "joined SETENV+ALL marker" "NOPASSWD: ALL is forbidden"

# ============================================================================
# Test 18 — prefix tag form SETENV:NOPASSWD: must still detect system binary
# ============================================================================
echo "[18] prefix SETENV tag + /bin/su"
reset_fixtures "18-prefix-setenv-su"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — prefix SETENV tag must not hide /bin/su
testuser ALL=(root) SETENV:NOPASSWD: /bin/su
EOF
exit_code=$(run_scanner)
assert_exit_code "prefix SETENV+su exit code" 2 "$exit_code"
assert_stderr_contains "prefix SETENV+su marker" "system-binary path /bin/su"

# ============================================================================
# Test 19 — joined tag form NOPASSWD:NOEXEC: must not hide ALL
# ============================================================================
echo "[19] joined NOEXEC tag + ALL"
reset_fixtures "19-joined-noexec-all"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — joined NOEXEC tag must not hide ALL
testuser ALL=(ALL) NOPASSWD:NOEXEC: ALL
EOF
exit_code=$(run_scanner)
assert_exit_code "joined NOEXEC+ALL exit code" 2 "$exit_code"
assert_stderr_contains "joined NOEXEC+ALL marker" "NOPASSWD: ALL is forbidden"

# ============================================================================
# Test 20 — prefix tag form NOEXEC:NOPASSWD: must still detect NOPASSWD
# ============================================================================
echo "[20] prefix NOEXEC tag + ALL"
reset_fixtures "20-prefix-noexec-all"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — prefix NOEXEC tag must not hide ALL
testuser ALL=(ALL) NOEXEC:NOPASSWD: ALL
EOF
exit_code=$(run_scanner)
assert_exit_code "prefix NOEXEC+ALL exit code" 2 "$exit_code"
assert_stderr_contains "prefix NOEXEC+ALL marker" "NOPASSWD: ALL is forbidden"

# ============================================================================
# Test 21 — joined tag form NOPASSWD:LOG_INPUT: must detect system binary
# ============================================================================
echo "[21] joined LOG_INPUT tag + /bin/su"
reset_fixtures "21-joined-loginput-su"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — joined LOG_INPUT tag must not hide /bin/su
testuser ALL=(root) NOPASSWD:LOG_INPUT: /bin/su
EOF
exit_code=$(run_scanner)
assert_exit_code "joined LOG_INPUT+su exit code" 2 "$exit_code"
assert_stderr_contains "joined LOG_INPUT+su marker" "system-binary path /bin/su"

# ============================================================================
# Test 22 — prefix tag form LOG_INPUT:NOPASSWD: must detect system binary
# ============================================================================
echo "[22] prefix LOG_INPUT tag + /bin/su"
reset_fixtures "22-prefix-loginput-su"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — prefix LOG_INPUT tag must not hide /bin/su
testuser ALL=(root) LOG_INPUT:NOPASSWD: /bin/su
EOF
exit_code=$(run_scanner)
assert_exit_code "prefix LOG_INPUT+su exit code" 2 "$exit_code"
assert_stderr_contains "prefix LOG_INPUT+su marker" "system-binary path /bin/su"

# ============================================================================
# Test 23 — glued-colon split form NOPASSWD :ALL must not drop the cmd spec
# ============================================================================
echo "[23] glued-colon split NOPASSWD :ALL"
reset_fixtures "23-glued-colon-all"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: tag-bypass regression — glued-colon split form must not drop spec
testuser ALL=(ALL) NOPASSWD :ALL
EOF
exit_code=$(run_scanner)
assert_exit_code "glued-colon ALL exit code" 2 "$exit_code"
assert_stderr_contains "glued-colon ALL marker" "NOPASSWD: ALL is forbidden"

# ============================================================================
# Test 24 — value-blind Defaults: a required name inside an env_keep value
#           must NOT satisfy the requirement
# ============================================================================
echo "[24] value-blind Defaults (env_keep value != satisfaction)"
reset_fixtures "24-value-blind-defaults"
# use_pty omitted as a real setting but present inside env_keep's value list.
# rm first: the baseline is mode 0440, which a non-root owner cannot truncate.
rm -f "$SUDOERS/00-defaults"
cat > "$SUDOERS/00-defaults" <<'EOF'
# RevealUI defense-in-depth sudoers defaults.
# justification: value-blind regression — env_keep value must not satisfy use_pty
Defaults    timestamp_timeout=10
Defaults    env_reset
Defaults    log_subcmds
Defaults    logfile=/var/log/sudo.log
Defaults    passwd_tries=3
Defaults    env_keep += use_pty
EOF
chmod 0440 "$SUDOERS/00-defaults"
exit_code=$(run_scanner)
assert_exit_code "value-blind exit code" 2 "$exit_code"
assert_stderr_contains "value-blind marker" "use_pty"

# ============================================================================
# Test 25 — comment context: a quoted '#' must not truncate a comma Cmnd list
# ============================================================================
echo "[25] quoted '#' does not drop comma-list member"
reset_fixtures "25-comment-in-comma-list"
cat > "$SUDOERS/testuser" <<'EOF'
# justification: comment-context regression — quoted # must not truncate the list
testuser ALL=(root) NOPASSWD: /usr/local/bin/x.sh "#c", /bin/su
EOF
exit_code=$(run_scanner)
assert_exit_code "comment-in-comma-list exit code" 2 "$exit_code"
assert_stderr_contains "comment-in-comma-list marker" "system-binary path /bin/su"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "============================================================"
echo "M-4 scanner smoke tests: $PASS passed, $FAIL failed"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
