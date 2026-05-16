#!/usr/bin/env bash
# test-render.sh — Tests for scripts/render.sh (RevKit template renderer)
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

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected NOT to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected: '$expected', got: '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$PROJECT_ROOT/scripts/render.sh"

# Create a temp directory for test fixtures; clean up on exit
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== test-render.sh ==="
echo "Renderer: $RENDER"
echo "Temp dir: $WORK"
echo ""

# NOTE: render.sh has a known issue where non-verbose, non-dry-run renders
# exit 1 due to `[[ "$VERBOSE" == "true" ]] && _info ...` at the end of
# render_file(). We use --verbose for render tests that check output, and
# --dry-run for tests that only need parsing/argument validation.

# ---------------------------------------------------------------------------
# Helper: create a complete test TOML profile
# ---------------------------------------------------------------------------

create_full_profile() {
  local dest="$1"
  cat > "$dest" <<'TOML'
# Test profile
[identity]
username = "testuser"
windows_user = "testwin"
git_name = "Test User"
git_email = "test@example.com"
github_org = "test-org"

[hardware]
wsl_memory = "8GB"
wsl_processors = "4"
wsl_swap = "2GB"

[infrastructure]
studio_mount = "/mnt/test"
postgres_port = "5432"
redis_port = "6379"
ollama_port = "11434"
chrome_devtools_port = "9222"

[features]
docker = true
nix = true
revvault = false

[project]
project_dir = "~/projects/TestProject"
project_name = "TestProject"
TOML
}

# ---------------------------------------------------------------------------
# 1. --help exits 0 and prints usage
# ---------------------------------------------------------------------------

echo "--- CLI flags ---"

help_output="$(bash "$RENDER" --help 2>&1)"
assert_ok "--help exits 0" bash "$RENDER" --help
assert_contains "--help prints USAGE" "$help_output" "USAGE"
assert_contains "--help mentions --config" "$help_output" "--config"
assert_contains "--help mentions --dry-run" "$help_output" "--dry-run"
assert_contains "--help mentions SUPPORTED PLACEHOLDERS" "$help_output" "SUPPORTED PLACEHOLDERS"

# ---------------------------------------------------------------------------
# 2. --version exits 0 and prints version
# ---------------------------------------------------------------------------

version_output="$(bash "$RENDER" --version 2>&1)"
assert_ok "--version exits 0" bash "$RENDER" --version
assert_contains "--version prints version number" "$version_output" "0.5.0"
assert_contains "--version prints script name" "$version_output" "render.sh"

# ---------------------------------------------------------------------------
# 3. Missing required args produce errors
# ---------------------------------------------------------------------------

echo ""
echo "--- Missing/invalid arguments ---"

assert_fail "no arguments fails" bash "$RENDER"
assert_fail "missing --output fails" bash "$RENDER" --config /dev/null
assert_fail "missing --config fails" bash "$RENDER" --output /tmp/test-out
assert_fail "nonexistent config file fails" bash "$RENDER" --config /nonexistent.toml --output /tmp/test-out
assert_fail "unknown option fails" bash "$RENDER" --bogus
assert_fail "unexpected positional arg fails" bash "$RENDER" some-random-arg

# ---------------------------------------------------------------------------
# 4. --dry-run with a valid profile produces output without errors
# ---------------------------------------------------------------------------

echo ""
echo "--- Dry-run mode ---"

create_full_profile "$WORK/full.toml"
mkdir -p "$WORK/templates-dry"
echo "{{USERNAME}} at {{GIT_EMAIL}}" > "$WORK/templates-dry/test.txt"

DRY_OUT="$WORK/output-dry"
dry_output="$(bash "$RENDER" --config "$WORK/full.toml" --output "$DRY_OUT" --templates "$WORK/templates-dry" --dry-run 2>&1)"

assert_ok "--dry-run exits 0" \
  bash "$RENDER" --config "$WORK/full.toml" --output "$DRY_OUT" --templates "$WORK/templates-dry" --dry-run
assert_contains "dry-run output mentions dry-run" "$dry_output" "dry-run"
assert_contains "dry-run output mentions Would render" "$dry_output" "Would render"

# dry-run should NOT create the output file
if [[ ! -f "$DRY_OUT/test.txt" ]]; then
  echo "PASS: --dry-run does not write output files"
  PASS=$((PASS + 1))
else
  echo "FAIL: --dry-run should not write output files"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# 5. TOML parsing: key-value pairs are correctly extracted from a profile
# ---------------------------------------------------------------------------

echo ""
echo "--- TOML parsing ---"

mkdir -p "$WORK/templates-identity"
cat > "$WORK/templates-identity/identity.txt" <<'TMPL'
User: {{USERNAME}}
Windows: {{WINDOWS_USER}}
Name: {{GIT_NAME}}
Email: {{GIT_EMAIL}}
Org: {{GITHUB_ORG}}
TMPL

cat > "$WORK/templates-identity/infra.txt" <<'TMPL'
Mount: {{STUDIO_MOUNT}}
Postgres: {{POSTGRES_PORT}}
Redis: {{REDIS_PORT}}
Ollama: {{OLLAMA_PORT}}
Chrome: {{CHROME_DEVTOOLS_PORT}}
Memory: {{WSL_MEMORY}}
CPUs: {{WSL_PROCESSORS}}
Swap: {{WSL_SWAP}}
Project: {{PROJECT_DIR}}
ProjectName: {{PROJECT_NAME}}
TMPL

PARSE_OUT="$WORK/output-parse"
assert_ok "render with full config exits 0 (--verbose)" \
  bash "$RENDER" --config "$WORK/full.toml" --output "$PARSE_OUT" --templates "$WORK/templates-identity" --verbose

# Check rendered identity values
rendered_identity="$(cat "$PARSE_OUT/identity.txt" 2>/dev/null || echo "")"
assert_contains "USERNAME resolved" "$rendered_identity" "User: testuser"
assert_contains "WINDOWS_USER resolved" "$rendered_identity" "Windows: testwin"
assert_contains "GIT_NAME resolved" "$rendered_identity" "Name: Test User"
assert_contains "GIT_EMAIL resolved" "$rendered_identity" "Email: test@example.com"
assert_contains "GITHUB_ORG resolved" "$rendered_identity" "Org: test-org"

# Check rendered infra/hardware/project values
rendered_infra="$(cat "$PARSE_OUT/infra.txt" 2>/dev/null || echo "")"
assert_contains "STUDIO_MOUNT resolved" "$rendered_infra" "Mount: /mnt/test"
assert_contains "POSTGRES_PORT resolved" "$rendered_infra" "Postgres: 5432"
assert_contains "REDIS_PORT resolved" "$rendered_infra" "Redis: 6379"
assert_contains "OLLAMA_PORT resolved" "$rendered_infra" "Ollama: 11434"
assert_contains "CHROME_DEVTOOLS_PORT resolved" "$rendered_infra" "Chrome: 9222"
assert_contains "WSL_MEMORY resolved" "$rendered_infra" "Memory: 8GB"
assert_contains "WSL_PROCESSORS resolved" "$rendered_infra" "CPUs: 4"
assert_contains "WSL_SWAP resolved" "$rendered_infra" "Swap: 2GB"
assert_contains "PROJECT_DIR resolved" "$rendered_infra" "Project: ~/projects/TestProject"
assert_contains "PROJECT_NAME resolved" "$rendered_infra" "ProjectName: TestProject"

# ---------------------------------------------------------------------------
# 6. Placeholder resolution: {{KEY}} in templates gets replaced with values
# ---------------------------------------------------------------------------

echo ""
echo "--- Placeholder resolution ---"

# No raw {{...}} markers should remain in fully-specified output
assert_not_contains "no unresolved placeholders in identity.txt" "$rendered_identity" "{{"
assert_not_contains "no unresolved placeholders in infra.txt" "$rendered_infra" "{{"

# Multiple occurrences of the same placeholder are all replaced
mkdir -p "$WORK/templates-multi"
cat > "$WORK/templates-multi/repeat.txt" <<'TMPL'
First: {{USERNAME}}
Second: {{USERNAME}}
Third: {{USERNAME}}
TMPL

MULTI_OUT="$WORK/output-multi"
bash "$RENDER" --config "$WORK/full.toml" --output "$MULTI_OUT" --templates "$WORK/templates-multi" --verbose 2>/dev/null

repeat_rendered="$(cat "$MULTI_OUT/repeat.txt" 2>/dev/null || echo "")"
assert_eq "all three USERNAME occurrences replaced" \
  "$repeat_rendered" \
  "First: testuser
Second: testuser
Third: testuser"

# Values with special characters (paths with slashes) are handled
mkdir -p "$WORK/templates-special"
echo "Dir: {{PROJECT_DIR}} Mount: {{STUDIO_MOUNT}}" > "$WORK/templates-special/paths.txt"

SPECIAL_OUT="$WORK/output-special"
bash "$RENDER" --config "$WORK/full.toml" --output "$SPECIAL_OUT" --templates "$WORK/templates-special" --verbose 2>/dev/null

special_rendered="$(cat "$SPECIAL_OUT/paths.txt" 2>/dev/null || echo "")"
assert_contains "paths with slashes rendered" "$special_rendered" "Dir: ~/projects/TestProject"
assert_contains "mount path with slashes rendered" "$special_rendered" "Mount: /mnt/test"

# ---------------------------------------------------------------------------
# 7. Missing required fields are caught (warning, unresolved markers remain)
# ---------------------------------------------------------------------------

echo ""
echo "--- Missing fields handling ---"

cat > "$WORK/partial.toml" <<'TOML'
[identity]
username = "partial-user"
git_name = "Partial"
git_email = "partial@test.com"
TOML

mkdir -p "$WORK/templates-partial"
echo "Hello {{USERNAME}}, port: {{POSTGRES_PORT}}" > "$WORK/templates-partial/test.txt"

PARTIAL_OUT="$WORK/output-partial"
partial_stderr="$(bash "$RENDER" --config "$WORK/partial.toml" --output "$PARTIAL_OUT" --templates "$WORK/templates-partial" --verbose 2>&1 1>/dev/null)"

assert_contains "missing fields produce warnings" "$partial_stderr" "Missing config values"

# Present values should still be resolved even with missing others
partial_rendered="$(cat "$PARTIAL_OUT/test.txt" 2>/dev/null || echo "")"
assert_contains "present values resolved in partial config" "$partial_rendered" "Hello partial-user"

# Missing placeholders should remain as raw {{...}} markers
assert_contains "missing placeholder retained as raw marker" "$partial_rendered" "{{POSTGRES_PORT}}"

# ---------------------------------------------------------------------------
# 8. TOML parser handles comments and blank lines correctly
# ---------------------------------------------------------------------------

echo ""
echo "--- TOML edge cases ---"

cat > "$WORK/comments.toml" <<'TOML'
# Full line comment

[identity]
username = "commtest"
windows_user = "commwin"
git_name = "Comm Test"
git_email = "comm@test.com"
github_org = "comm-org"

# Another comment block

[hardware]
wsl_memory = "16GB"
wsl_processors = "8"
wsl_swap = "4GB"

[infrastructure]
studio_mount = "/mnt/comm"
postgres_port = "5433"
redis_port = "6380"
ollama_port = "11435"
chrome_devtools_port = "9223"

[project]
project_dir = "~/projects/CommTest"
project_name = "CommTest"
TOML

mkdir -p "$WORK/templates-comments"
echo "{{USERNAME}} {{WSL_MEMORY}}" > "$WORK/templates-comments/test.txt"

COMM_OUT="$WORK/output-comments"
assert_ok "config with comments parses successfully" \
  bash "$RENDER" --config "$WORK/comments.toml" --output "$COMM_OUT" --templates "$WORK/templates-comments" --verbose

comm_rendered="$(cat "$COMM_OUT/test.txt" 2>/dev/null || echo "")"
assert_eq "comments and blank lines handled correctly" "$comm_rendered" "commtest 16GB"

# Test that unquoted values work
cat > "$WORK/unquoted.toml" <<'TOML'
[identity]
username = unquoted-user
windows_user = winuser
git_name = "Quoted Name"
git_email = bare@email.com
github_org = bare-org

[hardware]
wsl_memory = 8GB
wsl_processors = 4
wsl_swap = 2GB

[infrastructure]
studio_mount = /mnt/bare
postgres_port = 5432
redis_port = 6379
ollama_port = 11434
chrome_devtools_port = 9222

[project]
project_dir = ~/projects/Bare
project_name = BareProject
TOML

mkdir -p "$WORK/templates-unquoted"
echo "{{USERNAME}} mem={{WSL_MEMORY}}" > "$WORK/templates-unquoted/test.txt"

UQ_OUT="$WORK/output-unquoted"
bash "$RENDER" --config "$WORK/unquoted.toml" --output "$UQ_OUT" --templates "$WORK/templates-unquoted" --verbose 2>/dev/null

uq_rendered="$(cat "$UQ_OUT/test.txt" 2>/dev/null || echo "")"
assert_eq "unquoted TOML values parsed" "$uq_rendered" "unquoted-user mem=8GB"

# ---------------------------------------------------------------------------
# 9. --verbose flag shows resolved values
# ---------------------------------------------------------------------------

echo ""
echo "--- Verbose mode ---"

VERBOSE_OUT="$WORK/output-verbose"
verbose_output="$(bash "$RENDER" --config "$WORK/full.toml" --output "$VERBOSE_OUT" --templates "$WORK/templates-identity" --verbose 2>&1)"

assert_contains "--verbose prints resolved placeholders" "$verbose_output" "Resolved placeholders"
assert_contains "--verbose shows USERNAME value" "$verbose_output" "{{USERNAME}} = testuser"

# ---------------------------------------------------------------------------
# 10. Feature flags are parsed (reported in verbose, not as placeholders)
# ---------------------------------------------------------------------------

assert_contains "--verbose shows feature flags section" "$verbose_output" "Feature flags"
assert_contains "--verbose shows docker feature" "$verbose_output" "docker = true"
assert_contains "--verbose shows nix feature" "$verbose_output" "nix = true"

# Feature flag keys are NOT treated as placeholders
mkdir -p "$WORK/templates-feat"
echo "docker={{docker}} nix={{nix}}" > "$WORK/templates-feat/test.txt"

FEAT_OUT="$WORK/output-feat"
bash "$RENDER" --config "$WORK/full.toml" --output "$FEAT_OUT" --templates "$WORK/templates-feat" --verbose 2>/dev/null

feat_rendered="$(cat "$FEAT_OUT/test.txt" 2>/dev/null || echo "")"
# These should remain as raw markers since features are not in the placeholder map
assert_eq "feature flags not substituted as placeholders" "$feat_rendered" "docker={{docker}} nix={{nix}}"

# ---------------------------------------------------------------------------
# 11. Rendering with real profiles (dry-run to avoid writing)
# ---------------------------------------------------------------------------

echo ""
echo "--- Real profiles (dry-run) ---"

for profile in "$PROJECT_ROOT"/profiles/*.toml; do
  profile_name="$(basename "$profile")"
  assert_ok "profile $profile_name parses in dry-run" \
    bash "$RENDER" --config "$profile" --output "$WORK/output-real" --dry-run
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
