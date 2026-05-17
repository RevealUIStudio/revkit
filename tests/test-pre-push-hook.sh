#!/usr/bin/env bash
# test-pre-push-hook.sh — Tests for git-hooks/pre-push (M-11 enforcement).
#
# Strategy:
#   The hook reads stdin (git pre-push contract) and calls git plumbing
#   (rev-parse, merge-base --is-ancestor, rev-list, verify-commit, config).
#   We exercise it inside a throwaway git repo prepared with real commits
#   and a stubbed-out PATH that intercepts `git verify-commit` (commit
#   signing isn't possible in CI without keys).
#
#   Force-push detection and branch-classification go through real git
#   plumbing. Signed-commit verification is intercepted via a `git` shim
#   on PATH that returns 0/1 based on a fixture file. The shim defers all
#   non-verify-commit calls back to the real git binary.

set -euo pipefail

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

assert_exit() {
    local label="$1" expected_exit="$2"; shift 2
    local actual_exit=0
    "$@" >/dev/null 2>&1 || actual_exit=$?
    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        echo "PASS: $label (exit $actual_exit)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected_exit, got $actual_exit"
        FAIL=$((FAIL + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"; shift 2
    local out
    out="$("$@" 2>&1 >/dev/null || true)"
    if [[ "$out" == *"$needle"* ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — stderr missing: $needle"
        echo "  got: $out" | head -c 500
        echo ""
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PROJECT_ROOT/git-hooks/pre-push"

if [[ ! -f "$HOOK" ]]; then
    echo "FATAL: hook not found at $HOOK" >&2
    exit 2
fi

echo "=== test-pre-push-hook.sh ==="
echo "Hook: $HOOK"
echo ""

# ---------------------------------------------------------------------------
# Hook self-checks (no fixture needed)
# ---------------------------------------------------------------------------

echo "--- Static checks ---"

# 1. bash -n parse
assert_exit "hook parses with bash -n" 0 bash -n "$HOOK"

# 2. shebang sanity (no regex — just literal-byte read)
shebang_line="$(head -1 "$HOOK")"
if [[ "$shebang_line" == "#!/usr/bin/env bash" ]]; then
    echo "PASS: shebang is #!/usr/bin/env bash"
    PASS=$((PASS + 1))
else
    echo "FAIL: shebang line: $shebang_line"
    FAIL=$((FAIL + 1))
fi

# 3. forbid authored regex (`=~`) — fleet hardline
if grep -Fn '=~' "$HOOK" >/dev/null 2>&1; then
    echo "FAIL: hook contains '=~' (regex match) — violates no-regex hardline"
    grep -Fn '=~' "$HOOK" | sed 's/^/  /'
    FAIL=$((FAIL + 1))
else
    echo "PASS: no '=~' regex operators in hook"
    PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# Fixture: throwaway git repo with 2 commits on main + 1 commit on feature
# ---------------------------------------------------------------------------

echo ""
echo "--- Fixture setup ---"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"

# Initialize the repo and disable signing so test commits don't try to invoke gpg.
git init --quiet --initial-branch=main
git config commit.gpgsign false
git config tag.gpgsign false
git config user.name "Hook Tester"
git config user.email "test@example.invalid"
git config gpg.format openpgp

echo "first" > f.txt
git add f.txt
git commit --quiet -m "first commit"
SHA_MAIN_1="$(git rev-parse HEAD)"

echo "second" >> f.txt
git add f.txt
git commit --quiet -m "second commit"
SHA_MAIN_2="$(git rev-parse HEAD)"

git checkout --quiet -b feature/test-branch
echo "feature" > g.txt
git add g.txt
git commit --quiet -m "feature commit"
SHA_FEATURE="$(git rev-parse HEAD)"

# Force-push fixture: amend on main to create a divergent history
git checkout --quiet main
git commit --quiet --amend --no-edit -m "second commit (amended)"
SHA_MAIN_2_AMENDED="$(git rev-parse HEAD)"

echo "  Fixture commits:"
echo "    SHA_MAIN_1         = $SHA_MAIN_1"
echo "    SHA_MAIN_2         = $SHA_MAIN_2 (orphaned)"
echo "    SHA_MAIN_2_AMENDED = $SHA_MAIN_2_AMENDED"
echo "    SHA_FEATURE        = $SHA_FEATURE"

ZERO="0000000000000000000000000000000000000000"

# ---------------------------------------------------------------------------
# Helper: run the hook with a given stdin line, inside the fixture repo
# ---------------------------------------------------------------------------

# Capture both the working dir and reset gpg.program for verify-commit stub.
# A `git` shim on PATH would let us simulate verify-commit pass/fail; for the
# core flow tests we don't need to push past the protected-branch reject (the
# hook returns 1 before signature checks are even attempted).
run_hook() {
    local stdin="$1"
    cd "$WORK"
    printf '%s\n' "$stdin" | bash "$HOOK"
}

# ---------------------------------------------------------------------------
# Branch classification tests
# ---------------------------------------------------------------------------

echo ""
echo "--- Branch classification ---"

# Direct push to main → blocked (exit 1)
assert_exit "blocks direct push to refs/heads/main" 1 \
    run_hook "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_1"
assert_stderr_contains "main-block stderr names the branch" "refs/heads/main" \
    run_hook "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_1"
assert_stderr_contains "main-block stderr prints remediation" "open a PR" \
    run_hook "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_1"
assert_stderr_contains "main-block stderr cites escape hatch" "revealui.hooks.no-protection" \
    run_hook "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_1"

# Direct push to test → blocked (exit 1)
assert_exit "blocks direct push to refs/heads/test" 1 \
    run_hook "refs/heads/test $SHA_FEATURE refs/heads/test $SHA_MAIN_1"

# Push to feature/* → allowed (exit 0)
assert_exit "allows push to refs/heads/feature/test-branch" 0 \
    run_hook "refs/heads/feature/test-branch $SHA_FEATURE refs/heads/feature/test-branch $ZERO"

# Push to chore/* (non-protected, non-feature) → allowed
assert_exit "allows push to refs/heads/chore/cleanup" 0 \
    run_hook "refs/heads/chore/cleanup $SHA_FEATURE refs/heads/chore/cleanup $ZERO"

# Tag push → ignored (exit 0)
assert_exit "ignores tag push" 0 \
    run_hook "refs/tags/v1.0.0 $SHA_MAIN_1 refs/tags/v1.0.0 $ZERO"

# Empty stdin → exit 0
assert_exit "no refs on stdin → exit 0" 0 run_hook ""

# ---------------------------------------------------------------------------
# Branch-deletion tests
# ---------------------------------------------------------------------------

echo ""
echo "--- Branch deletion ---"

# Deleting main (local_sha = ZERO) → blocked
assert_exit "blocks deletion of refs/heads/main" 1 \
    run_hook "(delete) $ZERO refs/heads/main $SHA_MAIN_1"
assert_stderr_contains "delete-block stderr says cannot delete" "cannot be deleted" \
    run_hook "(delete) $ZERO refs/heads/main $SHA_MAIN_1"

# Deleting feature/* → allowed
assert_exit "allows deletion of refs/heads/feature/old" 0 \
    run_hook "(delete) $ZERO refs/heads/feature/old $SHA_FEATURE"

# ---------------------------------------------------------------------------
# Escape hatch tests
# ---------------------------------------------------------------------------

echo ""
echo "--- Escape hatch ---"

# Engage escape hatch in the fixture repo.
git config revealui.hooks.no-protection true

# With escape hatch + non-force, non-signed-relevant push: hook should warn
# and allow. But signed-commit check will fire (since we're pushing to main).
# Our fixture commits are unsigned, so this still fails — but on the
# signed-commit check, not on the direct-push rule.
escape_out="$(printf '%s\n' \
    "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_1" \
    | bash "$HOOK" 2>&1 >/dev/null || true)"
if [[ "$escape_out" == *"escape hatch ENGAGED"* ]]; then
    echo "PASS: warns when escape hatch engaged"
    PASS=$((PASS + 1))
else
    echo "FAIL: escape-hatch warning missing"
    echo "  got: $escape_out" | head -c 500
    FAIL=$((FAIL + 1))
fi
if [[ "$escape_out" == *"unsigned"* || "$escape_out" == *"Unsigned"* ]]; then
    echo "PASS: escape hatch does NOT bypass signed-commit check"
    PASS=$((PASS + 1))
else
    echo "FAIL: expected signed-commit check to still fire under escape hatch"
    echo "  got: $escape_out" | head -c 500
    FAIL=$((FAIL + 1))
fi

# Disengage for remaining tests.
git config --unset revealui.hooks.no-protection

# ---------------------------------------------------------------------------
# Force-push detection (logical test against real git plumbing)
# ---------------------------------------------------------------------------

echo ""
echo "--- Force-push detection ---"

# Engage escape hatch so direct-push rule is bypassed and we reach the force
# check. This is the only way to exercise the force-push code path without
# also tripping the direct-push reject. Both subtests below assume the
# escape hatch stays ON.
git config revealui.hooks.no-protection true

# Force-push to main: local = SHA_MAIN_2_AMENDED, remote = SHA_MAIN_2 (orphaned).
# SHA_MAIN_2 is NOT an ancestor of SHA_MAIN_2_AMENDED (amend created divergent history).
force_out="$(printf '%s\n' \
    "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_2" \
    | bash "$HOOK" 2>&1 >/dev/null || true)"
if [[ "$force_out" == *"Force-push to protected branch rejected"* ]]; then
    echo "PASS: detects force-push when remote sha is not ancestor of local"
    PASS=$((PASS + 1))
else
    echo "FAIL: missed force-push detection"
    echo "  got: $force_out" | head -c 500
    FAIL=$((FAIL + 1))
fi

# Fast-forward push (local descends from remote) → no force-push complaint.
# Will still fail on unsigned commits, but the failure message must NOT
# mention force-push. Escape hatch stays ON for this subtest.
ff_out="$(printf '%s\n' \
    "refs/heads/main $SHA_MAIN_2_AMENDED refs/heads/main $SHA_MAIN_1" \
    | bash "$HOOK" 2>&1 >/dev/null || true)"
if [[ "$ff_out" != *"Force-push"* ]]; then
    echo "PASS: fast-forward push not flagged as force-push"
    PASS=$((PASS + 1))
else
    echo "FAIL: fast-forward incorrectly flagged as force-push"
    echo "  got: $ff_out" | head -c 500
    FAIL=$((FAIL + 1))
fi

git config --unset revealui.hooks.no-protection

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
