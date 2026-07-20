#!/usr/bin/env bash
# rfg — RevFleet Grok launcher (WSL / native Linux / macOS)
#
# Starts a Grok session rooted in a RevFleet repo with Level 1 RevealUI MCP
# env preloaded from revvault (REVEALUI_MCP_TOKEN + URL). Same fleet-root
# resolution as rfc. See docs/rfg-launcher.md.
#
# Usage:
#   rfg                  # use $PWD if under ~/revfleet, else list repos
#   rfg revealui         # cd + load MCP env + exec grok
#   rfg revealui --help  # trailing args pass through to grok
#   rfg mint             # interactive device-token mint → revvault
#   rfg smoke            # auth/MCP health (no secret print)
#   rfg env              # print export lines for eval
#
# Override fleet root: REVFLEET_ROOT
# Skip MCP load: REVEALUI_MCP_ENV_SKIP=1
# Non-strict (launch even if token missing): REVEALUI_MCP_ENV_STRICT=0

set -euo pipefail

FLEET_ROOT="${REVFLEET_ROOT:-$HOME/revfleet}"

die() { echo "rfg: $*" >&2; exit 1; }

case "$(uname -s 2>/dev/null)" in
  Linux | Darwin) : ;;
  *) die "must run in a POSIX shell (WSL, Linux, or macOS)" ;;
esac

# --- MCP env load (self-contained: bootstrap copies this file alone) ----------
# Prefer shared lib when running from a revkit checkout; else use embedded.
_load_mcp_lib() {
  local candidates=(
    "${REVEALUI_ROOT:-}/shell/lib/revealui-mcp-env.sh"
    "$HOME/revfleet/revkit/shell/lib/revealui-mcp-env.sh"
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/shell/lib/revealui-mcp-env.sh"
  )
  local f
  for f in "${candidates[@]}"; do
    if [ -n "$f" ] && [ -f "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 1
}

_revealui_mcp_env_load_embedded() {
  local vault_path="${REVEALUI_MCP_TOKEN_VAULT_PATH:-revealui/dev/mcp/cli-token}"
  local url="${REVEALUI_MCP_URL:-https://api.revealui.com/api/mcp}"
  local strict="${REVEALUI_MCP_ENV_STRICT:-0}"
  local quiet="${REVEALUI_MCP_ENV_QUIET:-0}"
  local token=""

  export REVEALUI_MCP_TOKEN_VAULT_PATH="$vault_path"
  export REVEALUI_MCP_URL="$url"

  if ! command -v revvault >/dev/null 2>&1; then
    [ "$quiet" = 1 ] || echo "revealui-mcp-env: revvault not on PATH" >&2
    [ "$strict" = 1 ] && return 1
    return 0
  fi

  token="$(revvault get --full "$vault_path" 2>/dev/null || true)"
  if [ -z "${token// }" ]; then
    [ "$quiet" = 1 ] || {
      echo "revealui-mcp-env: empty/missing token at revvault path: $vault_path" >&2
      echo "  mint: rfg mint" >&2
    }
    [ "$strict" = 1 ] && return 1
    return 0
  fi

  case "$token" in
    rvui_dev_*)
      if [ "${#token}" -ne 73 ]; then
        [ "$quiet" = 1 ] || echo "revealui-mcp-env: token length unexpected (${#token})" >&2
        [ "$strict" = 1 ] && return 1
        return 0
      fi
      ;;
    *)
      [ "$quiet" = 1 ] || echo "revealui-mcp-env: token shape invalid" >&2
      [ "$strict" = 1 ] && return 1
      return 0
      ;;
  esac

  export REVEALUI_MCP_TOKEN="$token"
  return 0
}

if _load_mcp_lib; then
  :
else
  _revealui_mcp_env_load() { _revealui_mcp_env_load_embedded; }
fi

load_mcp_strict() {
  if [ "${REVEALUI_MCP_ENV_SKIP:-0}" = 1 ]; then
    return 0
  fi
  REVEALUI_MCP_ENV_STRICT="${REVEALUI_MCP_ENV_STRICT:-1}"
  export REVEALUI_MCP_ENV_STRICT
  _revealui_mcp_env_load
}

resolve_grok() {
  if command -v grok >/dev/null 2>&1; then command -v grok; return 0; fi
  local c
  for c in "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

list_repos() {
  local d
  for d in "$FLEET_ROOT"/*/ "$FLEET_ROOT"/.*/; do
    [ -e "${d}.git" ] || continue
    d="${d%/}"; echo "  ${d##*/}"
  done
}

cmd="${1:-}"
case "$cmd" in
  mint)
    shift || true
    if [ -x "$HOME/.grok/bin/revealui-mcp-mint" ]; then
      exec "$HOME/.grok/bin/revealui-mcp-mint" "$@"
    fi
    die "mint helper missing (~/.grok/bin/revealui-mcp-mint)"
    ;;
  smoke)
    shift || true
    if [ -x "$HOME/.grok/bin/revealui-mcp-smoke" ]; then
      exec "$HOME/.grok/bin/revealui-mcp-smoke" "$@"
    fi
    die "smoke helper missing (~/.grok/bin/revealui-mcp-smoke)"
    ;;
  env)
    REVEALUI_MCP_ENV_STRICT=1
    export REVEALUI_MCP_ENV_STRICT
    _revealui_mcp_env_load || exit 1
    printf 'export REVEALUI_MCP_TOKEN=%q\n' "$REVEALUI_MCP_TOKEN"
    printf 'export REVEALUI_MCP_URL=%q\n' "$REVEALUI_MCP_URL"
    printf 'export REVEALUI_MCP_TOKEN_VAULT_PATH=%q\n' "$REVEALUI_MCP_TOKEN_VAULT_PATH"
    exit 0
    ;;
  -h | --help | help)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

repo="${1:-}"
if [ -n "${repo:-}" ]; then
  shift
fi

if [ -z "${repo:-}" ]; then
  case "$PWD/" in
    "$FLEET_ROOT"/*) target="$PWD" ;;
    *)
      echo "rfg: name a fleet repo, e.g. 'rfg revealui'. Available:" >&2
      list_repos >&2
      exit 2
      ;;
  esac
else
  case "$repo" in
    -*)
      case "$PWD/" in
        "$FLEET_ROOT"/*) target="$PWD"; set -- "$repo" "$@" ;;
        *) die "name a fleet repo before grok flags, or cd into ~/revfleet/<repo>" ;;
      esac
      ;;
    *)
      target="$FLEET_ROOT/$repo"
      [ -d "$target" ] || die "no such fleet repo: '$repo' (under $FLEET_ROOT)"
      ;;
  esac
fi

grok_bin="$(resolve_grok)" || die "grok not found on PATH or in ~/.grok/bin / ~/.local/bin"

load_mcp_strict || die "MCP env not ready (mint with: rfg mint)"

cd "$target"
exec "$grok_bin" "$@"
