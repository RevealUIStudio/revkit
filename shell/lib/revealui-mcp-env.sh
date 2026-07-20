# shellcheck shell=bash
# revealui-mcp-env — shared loader for Level 1 RevealUI MCP attach
#
# Sourced by rfg.sh (and optional interactive helpers). Does NOT print secrets.
#
# Env overrides:
#   REVEALUI_MCP_TOKEN_VAULT_PATH  default: revealui/dev/mcp/cli-token
#   REVEALUI_MCP_URL               default: https://api.revealui.com/api/mcp
#   REVEALUI_MCP_ENV_STRICT=1      fail hard if token missing (default for rfg)
#   REVEALUI_MCP_ENV_QUIET=1       suppress warnings
#
# On success exports:
#   REVEALUI_MCP_TOKEN
#   REVEALUI_MCP_URL
#   REVEALUI_MCP_TOKEN_VAULT_PATH

_revealui_mcp_env_load() {
  local vault_path="${REVEALUI_MCP_TOKEN_VAULT_PATH:-revealui/dev/mcp/cli-token}"
  local default_url="https://api.revealui.com/api/mcp"
  local url="${REVEALUI_MCP_URL:-$default_url}"
  local strict="${REVEALUI_MCP_ENV_STRICT:-0}"
  local quiet="${REVEALUI_MCP_ENV_QUIET:-0}"
  local token=""
  local rv

  export REVEALUI_MCP_TOKEN_VAULT_PATH="$vault_path"
  export REVEALUI_MCP_URL="$url"

  if ! command -v revvault >/dev/null 2>&1; then
    [ "$quiet" = 1 ] || echo "revealui-mcp-env: revvault not on PATH" >&2
    [ "$strict" = 1 ] && return 1
    return 0
  fi

  rv="$(command -v revvault)"
  # --full: device tokens are single-line but keep the same posture as other secrets
  token="$("$rv" get --full "$vault_path" 2>/dev/null || true)"

  if [ -z "${token// }" ]; then
    [ "$quiet" = 1 ] || {
      echo "revealui-mcp-env: empty/missing token at revvault path: $vault_path" >&2
      echo "  mint: rfg mint   (or ~/.grok/bin/revealui-mcp-mint)" >&2
    }
    [ "$strict" = 1 ] && return 1
    return 0
  fi

  case "$token" in
    rvui_dev_[0-9a-f][0-9a-f]*)
      # length check without bashism that fails on ash: 9+64=73
      if [ "${#token}" -ne 73 ]; then
        [ "$quiet" = 1 ] || echo "revealui-mcp-env: token length unexpected (${#token})" >&2
        [ "$strict" = 1 ] && return 1
        return 0
      fi
      ;;
    *)
      [ "$quiet" = 1 ] || echo "revealui-mcp-env: token shape invalid (expected rvui_dev_ + 64 hex)" >&2
      [ "$strict" = 1 ] && return 1
      return 0
      ;;
  esac

  export REVEALUI_MCP_TOKEN="$token"
  return 0
}
