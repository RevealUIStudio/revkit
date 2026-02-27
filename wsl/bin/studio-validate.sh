#!/bin/bash
# Studio environment validation — health checks for DevKit tiers
# Installed to /usr/local/bin/ by bootstrap-wsl.sh
# Usage: studio validate [--verbose]

set -uo pipefail

# --- Config ---

VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
        *) echo "Usage: studio validate [--verbose]" >&2; exit 1 ;;
    esac
done

# Source base env if DEVKIT_TIER not set (direct invocation outside shell)
if [ -z "${DEVKIT_TIER:-}" ]; then
    _base="${REVEALUI_ROOT:-/mnt/c/Users/joshu/.revealui}/wsl/bashrc.d/00-base.sh"
    if [ -f "$_base" ]; then
        # shellcheck source=/dev/null
        source "$_base"
    fi
fi

# --- Counters ---

PASS=0
FAIL=0
SKIP=0

# --- Output helpers ---

check_pass() {
    PASS=$((PASS + 1))
    if [ "$VERBOSE" -eq 1 ]; then
        printf "  \033[32mPASS\033[0m  %s\n" "$1"
    fi
}

check_fail() {
    FAIL=$((FAIL + 1))
    printf "  \033[31mFAIL\033[0m  %s\n" "$1"
}

check_skip() {
    SKIP=$((SKIP + 1))
    if [ "$VERBOSE" -eq 1 ]; then
        printf "  \033[33mSKIP\033[0m  %s\n" "$1"
    fi
}

section() {
    printf "\n\033[1m%s\033[0m\n" "$1"
}

# --- Universal checks ---

section "Universal checks"

# 1. REVEALUI_ROOT set and valid
if [ -d "${REVEALUI_ROOT:-}/wsl" ]; then
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
for f in "${REVEALUI_ROOT:-}"/wsl/bashrc.d/*.sh; do
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
for f in "${REVEALUI_ROOT:-}"/wsl/bin/*.sh; do
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
compose_file="${REVEALUI_ROOT:-}/wsl/docker/compose.yml"
if [ -f "$compose_file" ]; then
    check_pass "Compose file exists"
else
    check_fail "Compose file missing: $compose_file"
fi

# 9. Connection string env vars set
if [ -n "${STUDIO_DATABASE_URL:-}" ] && [ -n "${STUDIO_REDIS_URL:-}" ]; then
    check_pass "Connection string env vars set"
else
    check_fail "Connection strings missing (DATABASE_URL=${STUDIO_DATABASE_URL:+set}, REDIS_URL=${STUDIO_REDIS_URL:+set})"
fi

# --- Tier-specific checks ---

if [ "${DEVKIT_TIER:-}" = "T0" ]; then
    section "T0 checks (Studio drive not mounted)"

    # 10. REVEALUI_STUDIO_MOUNTED unset
    if [ -z "${REVEALUI_STUDIO_MOUNTED:-}" ]; then
        check_pass "REVEALUI_STUDIO_MOUNTED unset"
    else
        check_fail "REVEALUI_STUDIO_MOUNTED should be unset at T0 (value=${REVEALUI_STUDIO_MOUNTED})"
    fi

    # 11. studio up refuses with tier error
    studio_err="$(studio-services.sh up 2>&1 || true)"
    if echo "$studio_err" | grep -qi "T0\|tier\|not mounted"; then
        check_pass "studio up correctly refuses at T0"
    else
        check_fail "studio up did not refuse at T0"
    fi

    # 12. /mnt/studio not a mountpoint
    if ! mountpoint -q /mnt/studio 2>/dev/null; then
        check_pass "/mnt/studio not mounted"
    else
        check_fail "/mnt/studio is mounted but tier is T0"
    fi

elif [ "${DEVKIT_TIER:-}" = "T1" ]; then
    section "T1 checks (Studio drive mounted)"

    # 13. /mnt/studio is a mountpoint
    if mountpoint -q /mnt/studio 2>/dev/null; then
        check_pass "/mnt/studio is mounted"
    else
        check_fail "/mnt/studio not mounted but tier is T1"
    fi

    # 14. REVEALUI_STUDIO_MOUNTED=1
    if [ "${REVEALUI_STUDIO_MOUNTED:-}" = "1" ]; then
        check_pass "REVEALUI_STUDIO_MOUNTED=1"
    else
        check_fail "REVEALUI_STUDIO_MOUNTED not set to 1 (${REVEALUI_STUDIO_MOUNTED:-<unset>})"
    fi

    # 15. Studio directory structure exists
    dirs_ok=true
    for d in databases/postgres databases/redis models cache; do
        if [ ! -d "/mnt/studio/$d" ]; then
            check_fail "Missing directory: /mnt/studio/$d"
            dirs_ok=false
        fi
    done
    if $dirs_ok; then
        check_pass "Studio directory structure intact"
    fi

    # 16. Studio drive free space > 5%
    used_pct="$(df --output=pcent /mnt/studio 2>/dev/null | tail -1 | tr -d ' %')"
    if [ -n "$used_pct" ] && [ "$used_pct" -lt 95 ]; then
        free_pct=$((100 - used_pct))
        check_pass "Studio drive free space: ${free_pct}%"
    else
        check_fail "Studio drive low on space (${used_pct:-?}% used)"
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
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^studio-postgres$'; then
            if docker exec studio-postgres pg_isready -q 2>/dev/null; then
                check_pass "Postgres container healthy"
            else
                check_fail "Postgres container running but not ready"
            fi
        else
            check_skip "Postgres container not running"
        fi

        # 19. Redis container healthy
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^studio-redis$'; then
            if docker exec studio-redis redis-cli ping 2>/dev/null | grep -q PONG; then
                check_pass "Redis container healthy"
            else
                check_fail "Redis container running but not responding"
            fi
        else
            check_skip "Redis container not running"
        fi

        # 20. Postgres on correct port (5433)
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^studio-postgres$'; then
            pg_port="$(docker port studio-postgres 5432 2>/dev/null || true)"
            if echo "$pg_port" | grep -q "5433"; then
                check_pass "Postgres mapped to port 5433"
            else
                check_fail "Postgres port mapping unexpected: ${pg_port:-none}"
            fi
        else
            check_skip "Postgres container not running — cannot check port"
        fi

        # 21. Redis on correct port (6380)
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^studio-redis$'; then
            redis_port="$(docker port studio-redis 6379 2>/dev/null || true)"
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
printf "\n"
if [ "$FAIL" -eq 0 ]; then
    printf "\033[32m%d passed\033[0m, %d failed, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$total"
else
    printf "%d passed, \033[31m%d failed\033[0m, %d skipped (%d total)\n" "$PASS" "$FAIL" "$SKIP" "$total"
fi

[ "$FAIL" -eq 0 ]
