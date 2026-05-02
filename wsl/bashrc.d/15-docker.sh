# shellcheck shell=bash
# Sandbox Docker infrastructure helpers

# Main CLI — delegates to sandbox-services.sh
sandbox() {
    local script="/usr/local/bin/sandbox-services.sh"
    if [ -x "$script" ]; then
        "$script" "$@"
    else
        echo "sandbox-services.sh not installed. Run bootstrap." >&2
        return 1
    fi
}

# Build SANDBOX_DATABASE_URL from wsl/docker/.env if present, avoiding hardcoded credentials
_docker_env="${REVEALUI_ROOT}/wsl/docker/.env"
if [ -f "$_docker_env" ]; then
    _pg_user=$(grep '^POSTGRES_USER=' "$_docker_env" | cut -d= -f2- | tr -d '"')
    _pg_pass=$(grep '^POSTGRES_PASSWORD=' "$_docker_env" | cut -d= -f2- | tr -d '"')
    _pg_db=$(grep '^POSTGRES_DB=' "$_docker_env" | cut -d= -f2- | tr -d '"')
fi
export SANDBOX_DATABASE_URL="postgresql://${_pg_user:-sandbox}:${_pg_pass:-sandbox}@localhost:5433/${_pg_db:-sandbox}"
unset _docker_env _pg_user _pg_pass _pg_db

export SANDBOX_REDIS_URL="redis://localhost:6380"
