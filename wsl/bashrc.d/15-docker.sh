# Studio Docker infrastructure helpers

# Main CLI — delegates to studio-services.sh
studio() {
    local script="/usr/local/bin/studio-services.sh"
    if [ -x "$script" ]; then
        "$script" "$@"
    else
        echo "studio-services.sh not installed. Run bootstrap." >&2
        return 1
    fi
}

# Connection string helpers (for use in project .env files)
export STUDIO_DATABASE_URL="postgresql://studio:studio@localhost:5433/studio"
export STUDIO_REDIS_URL="redis://localhost:6380"
