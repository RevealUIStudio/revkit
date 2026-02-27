#!/bin/bash
# Studio infrastructure service manager
# Installed to /usr/local/bin/ by bootstrap-wsl.sh
# Shell alias: studio() in bashrc.d/15-docker.sh

set -euo pipefail

COMPOSE_DIR="${REVEALUI_ROOT:-/mnt/c/Users/joshu/.revealui}/wsl/docker"
COMPOSE_FILE="$COMPOSE_DIR/compose.yml"

# --- Helpers ---

die() { echo "error: $*" >&2; exit 1; }

require_tier() {
    if [ "${DEVKIT_TIER:-T0}" = "T0" ]; then
        die "Studio drive not mounted (tier T0). Mount it first: mount-studio-drive.sh"
    fi
}

ensure_docker() {
    if ! command -v docker &>/dev/null; then
        die "docker not found. Install Docker Engine first."
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo "Starting Docker daemon..."
        sudo systemctl start docker
        # Wait for daemon to be ready
        local retries=10
        while ! docker info &>/dev/null 2>&1; do
            retries=$((retries - 1))
            if [ "$retries" -le 0 ]; then
                die "Docker daemon failed to start"
            fi
            sleep 1
        done
    fi
}

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

usage() {
    cat <<EOF
Studio infrastructure manager

Usage: studio <command> [options]

Commands:
  up [--ai]      Start services (add --ai for Ollama)
  down           Stop all services
  status         Show container status and health
  logs [service] Tail logs (optionally for a specific service)
  pull           Pull latest images
  psql [args]    Connect to Postgres via psql
  redis-cli      Connect to Redis via redis-cli
  validate       Run environment health checks
  help           Show this help message
EOF
}

# --- Commands ---

cmd_up() {
    require_tier
    ensure_docker

    if [ ! -f "$COMPOSE_FILE" ]; then
        die "Compose file not found: $COMPOSE_FILE"
    fi

    local profiles=()
    for arg in "$@"; do
        case "$arg" in
            --ai|ai) profiles+=(--profile ai) ;;
            *) die "Unknown option: $arg" ;;
        esac
    done

    echo "Starting Studio services..."
    if [ ${#profiles[@]} -gt 0 ]; then
        compose "${profiles[@]}" up -d
    else
        compose up -d
    fi
    echo ""
    compose ps
}

cmd_down() {
    ensure_docker
    echo "Stopping Studio services..."
    compose --profile ai down
}

cmd_status() {
    ensure_docker
    compose ps -a
}

cmd_logs() {
    ensure_docker
    if [ $# -gt 0 ]; then
        compose logs -f "$1"
    else
        compose logs -f
    fi
}

cmd_pull() {
    ensure_docker
    echo "Pulling latest images..."
    compose --profile ai pull
}

cmd_psql() {
    ensure_docker
    docker exec -it studio-postgres psql -U "${POSTGRES_USER:-studio}" -d "${POSTGRES_DB:-studio}" "$@"
}

cmd_redis_cli() {
    ensure_docker
    docker exec -it studio-redis redis-cli "$@"
}

# --- Main ---

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

command="$1"
shift

case "$command" in
    up)        cmd_up "$@" ;;
    down)      cmd_down ;;
    status)    cmd_status ;;
    logs)      cmd_logs "$@" ;;
    pull)      cmd_pull ;;
    psql)      cmd_psql "$@" ;;
    redis-cli) cmd_redis_cli "$@" ;;
    validate)  exec /usr/local/bin/studio-validate.sh "$@" ;;
    help|-h|--help) usage ;;
    *)         die "Unknown command: $command. Run 'studio help' for usage." ;;
esac
