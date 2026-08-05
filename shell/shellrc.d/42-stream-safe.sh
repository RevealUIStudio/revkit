# shellcheck shell=bash
# Stream-safe vs vault-private secret profiles (OBS / YouTube / shared screen).
#
# Stream terminal (default when STREAM_SAFE=1):
#   - Paths and with-secrets / revvault run only
#   - revvault get --full / --clip refuse unless REVVAULT_ALLOW_PRINT=1
#   - Prompt shows "stream"
#
# Vault-private terminal (screenshare / window capture OFF):
#   source this with:  vault-private
#   or:  export REVVAULT_ALLOW_PRINT=1; unset STREAM_SAFE
#   - Full get/clip allowed
#   - Prompt shows "VAULT"
#
# Docs: .jv ADR 2026-08-05-stream-safe-secrets + GAP-468

stream-safe() {
    export STREAM_SAFE=1
    export REVVAULT_STREAM_SAFE=1
    unset REVVAULT_ALLOW_PRINT 2>/dev/null || true
    printf 'stream-safe ON: secrets only via revvault run / with-secrets (no TTY print/clip).\n' >&2
}

vault-private() {
    unset STREAM_SAFE REVVAULT_STREAM_SAFE 2>/dev/null || true
    export REVVAULT_ALLOW_PRINT=1
    printf 'vault-private ON: full get/clip allowed. Keep this window out of OBS.\n' >&2
}

# Optional: auto stream-safe when RV_STREAM=1 is set by a dedicated terminal profile
if [ "${RV_STREAM:-}" = "1" ] && [ -z "${REVVAULT_ALLOW_PRINT:-}" ]; then
    export STREAM_SAFE=1
    export REVVAULT_STREAM_SAFE=1
fi
