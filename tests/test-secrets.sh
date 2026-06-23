#!/usr/bin/env bash
# test-secrets.sh — Tests for shell/shellrc.d/40-secrets.sh (passenv security)
set -euo pipefail

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_ok() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $label (should have failed)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_SH="$PROJECT_ROOT/shell/shellrc.d/40-secrets.sh"

echo "=== test-secrets.sh ==="
echo "Source:   $SECRETS_SH"
echo ""

# We test passenv validation in a subshell to isolate side effects.
# passenv needs REVVAULT_STORE set and the `revvault` command, but for
# validation tests (which reject before calling revvault) we can mock
# the environment enough to test the guard logic.

# ---------------------------------------------------------------------------
# Helper: run passenv in an isolated subshell
# ---------------------------------------------------------------------------
# Sources 40-secrets.sh, sets a dummy REVVAULT_STORE, stubs `revvault` to
# return a dummy value (so valid-name tests can reach the export path),
# then calls passenv with the given arguments.

run_passenv() {
  (
    # Source the secrets file
    source "$SECRETS_SH"

    # Set up minimal environment so passenv doesn't bail on REVVAULT_STORE
    export REVVAULT_STORE="/tmp/fake-revvault-store"
    export PASSAGE_DIR="$REVVAULT_STORE"  # backward-compat alias

    # Stub revvault to return a value — only reached for valid names
    revvault() {
      echo "dummy-secret-value"
    }
    export -f revvault

    passenv "$@"
  )
}

# ---------------------------------------------------------------------------
# 1. Invalid variable names are rejected
# ---------------------------------------------------------------------------

echo "--- Variable name validation ---"

# Names with spaces
assert_fail "rejects name with space" run_passenv "BAD NAME" "some/path"

# Names starting with digits
assert_fail "rejects name starting with digit" run_passenv "1INVALID" "some/path"
assert_fail "rejects name starting with digit (0)" run_passenv "0VAR" "some/path"

# Names with special characters
assert_fail "rejects name with dash" run_passenv "BAD-NAME" "some/path"
assert_fail "rejects name with dot" run_passenv "BAD.NAME" "some/path"
assert_fail "rejects name with slash" run_passenv "BAD/NAME" "some/path"
assert_fail "rejects name with equals" run_passenv "BAD=NAME" "some/path"
assert_fail "rejects empty name" run_passenv "" "some/path"

# Check that error message mentions invalid
invalid_err="$(run_passenv "BAD NAME" "some/path" 2>&1 || true)"
assert_contains "invalid name error message" "$invalid_err" "invalid variable name"

# ---------------------------------------------------------------------------
# 2. Dangerous/protected variables are blocked
# ---------------------------------------------------------------------------

echo ""
echo "--- Protected variable blocking ---"

assert_fail "blocks PATH" run_passenv "PATH" "some/path"
assert_fail "blocks LD_PRELOAD" run_passenv "LD_PRELOAD" "some/path"
assert_fail "blocks LD_LIBRARY_PATH" run_passenv "LD_LIBRARY_PATH" "some/path"
assert_fail "blocks HOME" run_passenv "HOME" "some/path"
assert_fail "blocks SHELL" run_passenv "SHELL" "some/path"
assert_fail "blocks USER" run_passenv "USER" "some/path"
assert_fail "blocks LOGNAME" run_passenv "LOGNAME" "some/path"
assert_fail "blocks IFS" run_passenv "IFS" "some/path"

# Verify error message mentions "protected"
path_err="$(run_passenv "PATH" "some/path" 2>&1 || true)"
assert_contains "protected variable error message" "$path_err" "protected variable"

# ---------------------------------------------------------------------------
# 3. Valid variable names are accepted
# ---------------------------------------------------------------------------

echo ""
echo "--- Valid variable names ---"

assert_ok "accepts simple uppercase name" run_passenv "MY_SECRET" "some/path"
assert_ok "accepts lowercase name" run_passenv "my_secret" "some/path"
assert_ok "accepts mixed case" run_passenv "MySecret_123" "some/path"
assert_ok "accepts underscore-prefixed name" run_passenv "_PRIVATE" "some/path"
assert_ok "accepts single letter" run_passenv "X" "some/path"
assert_ok "accepts name with numbers" run_passenv "API_KEY_2" "some/path"

# ---------------------------------------------------------------------------
# 4. REVVAULT_STORE must be set
# ---------------------------------------------------------------------------

echo ""
echo "--- REVVAULT_STORE requirement ---"

# Run passenv without REVVAULT_STORE set
no_dir_result="$(
  (
    source "$SECRETS_SH"
    unset REVVAULT_STORE
    unset PASSAGE_DIR
    passenv "VALID_NAME" "some/path"
  ) 2>&1 || true
)"
no_dir_exit=$?

# The function should fail when REVVAULT_STORE is unset
if [[ $no_dir_exit -ne 0 ]] || [[ "$no_dir_result" == *"REVVAULT_STORE"* ]] || [[ "$no_dir_result" == *"PASSAGE_DIR"* ]]; then
  echo "PASS: passenv fails when REVVAULT_STORE is unset"
  PASS=$((PASS + 1))
else
  echo "FAIL: passenv should fail when REVVAULT_STORE is unset"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# 5. passenv-file also blocks protected variables
# ---------------------------------------------------------------------------

echo ""
echo "--- passenv-file protected variable blocking ---"

# Test that passenv-file skips protected variables in content.
# We need to stub revvault/passage to return env-file content.
pf_output="$(
  (
    source "$SECRETS_SH"
    export PASSAGE_DIR="/tmp/fake-passage-store"

    # Stub passage too (defensive); 40-secrets.sh actually reads via revvault
    passage() {
      # Return content that includes a protected variable
      printf 'SAFE_VAR=good\nPATH=/evil\nANOTHER_SAFE=also_good\n'
    }
    export -f passage

    # revvault is the canonical backend 40-secrets.sh reads (passenv-file)
    revvault() {
      printf 'SAFE_VAR=good\nPATH=/evil\nANOTHER_SAFE=also_good\n'
    }
    export -f revvault

    passenv-file "test/path" 2>&1
  )
)"

assert_contains "passenv-file warns about PATH override attempt" "$pf_output" "protected variable"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
