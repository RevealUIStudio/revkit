# shellcheck shell=bash
# Sandbox Docker infrastructure helpers

# Main CLI — builds DB URL at call time (not at shell startup) so credentials
# are never broadcast into the global interactive environment.
sandbox() {
    local script="/usr/local/bin/sandbox-services.sh"
    if [ ! -x "$script" ]; then
        echo "sandbox-services.sh not installed. Run bootstrap." >&2
        return 1
    fi
    local _denv="${REVEALUI_ROOT}/shell/docker/.env"
    local _u="" _p="" _d=""
    if [ -f "$_denv" ]; then
        _u=$(grep '^POSTGRES_USER=' "$_denv" | cut -d= -f2- | tr -d '"')
        _p=$(grep '^POSTGRES_PASSWORD=' "$_denv" | cut -d= -f2- | tr -d '"')
        _d=$(grep '^POSTGRES_DB=' "$_denv" | cut -d= -f2- | tr -d '"')
    fi
    SANDBOX_DATABASE_URL="postgresql://${_u:-sandbox}:${_p:-sandbox}@localhost:5433/${_d:-sandbox}" \
    SANDBOX_REDIS_URL="redis://localhost:6380" \
    POSTGRES_USER="${_u:-sandbox}" \
    POSTGRES_DB="${_d:-sandbox}" \
    PGPASSWORD="${_p:-sandbox}" \
    "$script" "$@"
}

export SANDBOX_REDIS_URL="redis://localhost:6380"
