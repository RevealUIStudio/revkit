#!/bin/bash
# Sandbox environment validation — health checks for DevKit tiers
# Installed to /usr/local/bin/ by bootstrap-wsl.sh
# Usage: sandbox validate [--verbose] [--json]

set -uo pipefail

# --- Config ---

VERBOSE=0
JSON_MODE=0
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
        --json) JSON_MODE=1 ;;
        *) echo "Usage: sandbox validate [--verbose] [--json]" >&2; exit 1 ;;
    esac
done

# Source base env if DEVKIT_TIER not set (direct invocation outside shell)
if [ -z "${DEVKIT_TIER:-}" ]; then
    _base=""
    # Explicit override wins
    if [ -n "${REVEALUI_ROOT:-}" ] && [ -f "${REVEALUI_ROOT}/shell/shellrc.d/00-base.sh" ]; then
        _base="${REVEALUI_ROOT}/shell/shellrc.d/00-base.sh"
    else
        # Discover via the same paths bashrc.d/00-base.sh searches
        for _candidate in /mnt/c/Users/*/.revealui /mnt/?/.revealui /mnt/?/professional/.revealui; do
            if [ -f "$_candidate/shell/shellrc.d/00-base.sh" ]; then
                _base="$_candidate/shell/shellrc.d/00-base.sh"
                break
            fi
        done
    fi
    if [ -n "$_base" ] && [ -f "$_base" ]; then
        # shellcheck source=/dev/null
        source "$_base"
    fi
fi

# --- Counters ---

PASS=0
FAIL=0
SKIP=0

# --- JSON helpers ---

# Escape a string for safe JSON embedding (handles \, ", newlines, tabs, control chars)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"    # backslash
    s="${s//\"/\\\"}"    # double quote
    s="${s//$'\n'/\\n}"  # newline
    s="${s//$'\t'/\\t}"  # tab
    s="${s//$'\r'/\\r}"  # carriage return
    printf '%s' "$s"
}

# JSON checks array — each entry is a pre-formatted JSON object string
JSON_CHECKS=()

# Append a check result to the JSON array
json_add_check() {
    local name status detail
    name="$(json_escape "$1")"
    status="$2"
    detail="$(json_escape "$3")"
    JSON_CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\"}")
}

# --- Output helpers ---

check_pass() {
    local msg="$1"
    PASS=$((PASS + 1))
    if [ "$JSON_MODE" -eq 1 ]; then
        json_add_check "$msg" "pass" "$msg"
    elif [ "$VERBOSE" -eq 1 ]; then
        printf "  \033[32mPASS\033[0m  %s\n" "$msg"
    fi
}

check_fail() {
    local msg="$1"
    FAIL=$((FAIL + 1))
    if [ "$JSON_MODE" -eq 1 ]; then
        json_add_check "$msg" "fail" "$msg"
    else
        printf "  \033[31mFAIL\033[0m  %s\n" "$msg"
    fi
}

check_skip() {
    local msg="$1"
    SKIP=$((SKIP + 1))
    if [ "$JSON_MODE" -eq 1 ]; then
        json_add_check "$msg" "skip" "$msg"
    elif [ "$VERBOSE" -eq 1 ]; then
        printf "  \033[33mSKIP\033[0m  %s\n" "$msg"
    fi
}

section() {
    if [ "$JSON_MODE" -eq 0 ]; then
        printf "\n\033[1m%s\033[0m\n" "$1"
    fi
}

# --- Universal checks ---

section "Universal checks"

# 1. REVEALUI_ROOT set and valid
if [ -f "${REVEALUI_ROOT:-}/shell/shellrc.d/00-base.sh" ]; then
    check_pass "REVEALUI_ROOT set and valid ($REVEALUI_ROOT)"
else
    check_fail "REVEALUI_ROOT not set or invalid (${REVEALUI_ROOT:-<unset>})"
fi

# 2. DEVKIT_TIER is T0 or T1
if [[ "${DEVKIT_TIER:-}" =~ ^T[01]$ ]]; then
    check_pass "DEVKIT_TIER=$DEVKIT_TIER"
else
    check_fail "DEVKIT_TIER not T0 or T1 (${DEVKIT_TIER:-<unset>})"
fi

# 3. bashrc.d scripts parse cleanly
bashrc_ok=true
for f in "${REVEALUI_ROOT:-}"/shell/shellrc.d/*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f" 2>/dev/null; then
        check_fail "bashrc.d syntax error: $(basename "$f")"
        bashrc_ok=false
    fi
done
if $bashrc_ok; then
    check_pass "bashrc.d scripts parse cleanly"
fi

# 4. Helper scripts installed in /usr/local/bin
helpers_ok=true
for f in "${REVEALUI_ROOT:-}"/shell/bin/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    installed="/usr/local/bin/$name"
    if [ ! -f "$installed" ]; then
        check_fail "Helper not installed: $name"
        helpers_ok=false
    fi
done
if $helpers_ok; then
    check_pass "Helper scripts installed in /usr/local/bin"
fi

# 5. Git identity configured
git_name="$(git config user.name 2>/dev/null || true)"
git_email="$(git config user.email 2>/dev/null || true)"
if [ -n "$git_name" ] && [ -n "$git_email" ]; then
    check_pass "Git identity: $git_name <$git_email>"
else
    check_fail "Git identity not configured (name=${git_name:-<unset>}, email=${git_email:-<unset>})"
fi

# 6. Node.js available
if command -v node &>/dev/null; then
    check_pass "Node.js $(node --version)"
else
    check_fail "Node.js not found"
fi

# 7. systemd running
systemd_state="$(systemctl is-system-running 2>/dev/null || true)"
if [ "$systemd_state" = "running" ] || [ "$systemd_state" = "degraded" ]; then
    check_pass "systemd: $systemd_state"
else
    check_fail "systemd: ${systemd_state:-not available}"
fi

# 8. Compose file exists
compose_file="${REVEALUI_ROOT:-}/shell/docker/compose.yml"
if [ -f "$compose_file" ]; then
    check_pass "Compose file exists"
else
    check_fail "Compose file missing: $compose_file"
fi

# 9. Connection strings reachable.
#    REDIS_URL is exported globally. DATABASE_URL is built at point of use by the
#    sandbox() shell function so DB credentials are never broadcast into the global
#    interactive environment. So require REDIS_URL in the environment and verify
#    DATABASE_URL is constructible: either already set (e.g. inside the sandbox()
#    wrapper or CI) or its source .env is present with POSTGRES_* keys.
db_url_state="missing"
if [ -n "${SANDBOX_DATABASE_URL:-}" ]; then
    db_url_state="set"
else
    sandbox_denv="${REVEALUI_ROOT:-}/shell/docker/.env"
    if [ -f "$sandbox_denv" ] && grep -qF 'POSTGRES_USER=' "$sandbox_denv"; then
        db_url_state="constructible"
    fi
fi

if [ -n "${SANDBOX_REDIS_URL:-}" ] && [ "$db_url_state" != "missing" ]; then
    check_pass "Connection strings OK (REDIS_URL set, DATABASE_URL $db_url_state)"
else
    check_fail "Connection strings missing (REDIS_URL=${SANDBOX_REDIS_URL:+set}, DATABASE_URL=$db_url_state; copy shell/docker/.env.example to .env)"
fi

# --- Tier-specific checks ---

if [ "${DEVKIT_TIER:-}" = "T0" ]; then
    section "T0 checks (Sandbox drive not mounted)"

    # 10. REVEALUI_SANDBOX_MOUNTED unset
    if [ -z "${REVEALUI_SANDBOX_MOUNTED:-}" ]; then
        check_pass "REVEALUI_SANDBOX_MOUNTED unset"
    else
        check_fail "REVEALUI_SANDBOX_MOUNTED should be unset at T0 (value=${REVEALUI_SANDBOX_MOUNTED})"
    fi

    # 11. sandbox up refuses with tier error
    sandbox_err="$(sandbox-services.sh up 2>&1 || true)"
    if echo "$sandbox_err" | grep -qi "T0\|tier\|not mounted"; then
        check_pass "sandbox up correctly refuses at T0"
    else
        check_fail "sandbox up did not refuse at T0"
    fi

    # 12. /mnt/sandbox not a mountpoint
    if ! mountpoint -q /mnt/sandbox 2>/dev/null; then
        check_pass "/mnt/sandbox not mounted"
    else
        check_fail "/mnt/sandbox is mounted but tier is T0"
    fi

elif [ "${DEVKIT_TIER:-}" = "T1" ]; then
    section "T1 checks (Sandbox drive mounted)"

    # 13. /mnt/sandbox is a mountpoint
    if mountpoint -q /mnt/sandbox 2>/dev/null; then
        check_pass "/mnt/sandbox is mounted"
    else
        check_fail "/mnt/sandbox not mounted but tier is T1"
    fi

    # 14. REVEALUI_SANDBOX_MOUNTED=1
    if [ "${REVEALUI_SANDBOX_MOUNTED:-}" = "1" ]; then
        check_pass "REVEALUI_SANDBOX_MOUNTED=1"
    else
        check_fail "REVEALUI_SANDBOX_MOUNTED not set to 1 (${REVEALUI_SANDBOX_MOUNTED:-<unset>})"
    fi

    # 15. Sandbox directory structure exists
    dirs_ok=true
    for d in databases/postgres databases/redis models cache; do
        if [ ! -d "/mnt/sandbox/$d" ]; then
            check_fail "Missing directory: /mnt/sandbox/$d"
            dirs_ok=false
        fi
    done
    if $dirs_ok; then
        check_pass "Sandbox directory structure intact"
    fi

    # 16. Sandbox drive free space > 5%
    used_pct="$(df --output=pcent /mnt/sandbox 2>/dev/null | tail -1 | tr -d ' %')"
    if [ -n "$used_pct" ] && [ "$used_pct" -lt 95 ]; then
        free_pct=$((100 - used_pct))
        check_pass "Sandbox drive free space: ${free_pct}%"
    else
        check_fail "Sandbox drive low on space (${used_pct:-?}% used)"
    fi

    # 17. Docker daemon reachable
    docker_ok=false
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        check_pass "Docker daemon reachable"
        docker_ok=true
    else
        check_skip "Docker daemon not running — skipping container checks"
    fi

    if $docker_ok; then
        # 18. Postgres container healthy
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^sandbox-postgres$'; then
            if docker exec sandbox-postgres pg_isready -q 2>/dev/null; then
                check_pass "Postgres container healthy"
            else
                check_fail "Postgres container running but not ready"
            fi
        else
            check_skip "Postgres container not running"
        fi

        # 19. Redis container healthy
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^sandbox-redis$'; then
            if docker exec sandbox-redis redis-cli ping 2>/dev/null | grep -q PONG; then
                check_pass "Redis container healthy"
            else
                check_fail "Redis container running but not responding"
            fi
        else
            check_skip "Redis container not running"
        fi

        # 20. Postgres on correct port (5433)
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^sandbox-postgres$'; then
            pg_port="$(docker port sandbox-postgres 5432 2>/dev/null || true)"
            if echo "$pg_port" | grep -q "5433"; then
                check_pass "Postgres mapped to port 5433"
            else
                check_fail "Postgres port mapping unexpected: ${pg_port:-none}"
            fi
        else
            check_skip "Postgres container not running — cannot check port"
        fi

        # 21. Redis on correct port (6380)
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^sandbox-redis$'; then
            redis_port="$(docker port sandbox-redis 6379 2>/dev/null || true)"
            if echo "$redis_port" | grep -q "6380"; then
                check_pass "Redis mapped to port 6380"
            else
                check_fail "Redis port mapping unexpected: ${redis_port:-none}"
            fi
        else
            check_skip "Redis container not running — cannot check port"
        fi
    fi
fi

# --- Summary ---

total=$((PASS + FAIL + SKIP))

if [ "$JSON_MODE" -eq 1 ]; then
    # Build the checks array
    checks_json=""
    for i in "${!JSON_CHECKS[@]}"; do
        if [ "$i" -gt 0 ]; then
            checks_json="${checks_json},"
        fi
        checks_json="${checks_json}${JSON_CHECKS[$i]}"
    done

    tier_val="$(json_escape "${DEVKIT_TIER:-unknown}")"
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Use jq for pretty-printing if available, otherwise emit compact JSON
    json_output="{\"tier\":\"$tier_val\",\"timestamp\":\"$timestamp\",\"checks\":[$checks_json],\"summary\":{\"pass\":$PASS,\"fail\":$FAIL,\"skip\":$SKIP,\"total\":$total}}"
    if command -v jq &>/dev/null; then
        printf '%s' "$json_output" | jq .
    else
        printf '%s\n' "$json_output"
    fi
else
    printf "\n"
    if [ "$FAIL" -eq 0 ]; then
        printf "\033[32m%d passed\033[0m, %d failed, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$total"
    else
        printf "%d passed, \033[31m%d failed\033[0m, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$total"
    fi
fi

[ "$FAIL" -eq 0 ]
