#!/usr/bin/env bash
# rfg — RevFleet Grok launcher (WSL / native Linux / macOS)
#
# Starts a Grok session rooted in a RevFleet repo with Level 1 RevealUI MCP
# env preloaded from revvault (REVEALUI_MCP_TOKEN + URL). Same fleet-root
# resolution as rfc. See docs/rfg-launcher.md.
#
# Usage:
#   rfg                  # use $PWD if inside the fleet (root or repo)
#   rfg revealui         # cd product checkout + load MCP env + exec grok
#   rfg / rfg . at fleet root starts a fleet-root session (does not exit 2)
#   rfg revealui --help  # trailing args pass through to grok
#   rfg revealui --worktree=label "…"  # worktree base = integration ref
#   rfg mint             # interactive device-token mint → revvault
#   rfg smoke            # auth/MCP health (no secret print)
#   rfg env              # print non-secret MCP URL + vault path (never the token)
#   rfg bootstrap [path] # Rift-inspired: write .env.worktree (hash ports)
#   rfg claim …          # claim acquire|release|list|check|sweep
#   rfg open <repo> <label> [--claim surface] [--no-agent]
#                        # create ~/revfleet/.wt/<label> from integration ref,
#                        # bootstrap env, optional claim, optional grok
#
# Override fleet root: REVFLEET_ROOT
# Skip MCP load: REVEALUI_MCP_ENV_SKIP=1
# Non-strict (launch even if token missing): REVEALUI_MCP_ENV_STRICT=0
# Skip worktree-ref inject: RFG_WORKTREE_REF_SKIP=1
# Force worktree base ref: RFG_WORKTREE_REF=test
# Skip Grok vendor-hook attach: RFG_GROK_ATTACH_SKIP=1

set -euo pipefail

_load_fleet_root_lib() {
  local f
  for f in \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/fleet-root.sh" \
    "$HOME/revealfleet/revkit/shell/lib/fleet-root.sh" \
    "$HOME/revfleet/revkit/shell/lib/fleet-root.sh"
  do
    if [ -n "$f" ] && [ -f "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 1
}
_load_fleet_root_lib || rfg_resolve_fleet_root() { printf '%s\n' "${REVFLEET_ROOT:-$HOME/revealfleet}"; }
FLEET_ROOT="$(rfg_resolve_fleet_root)"

die() { echo "rfg: $*" >&2; exit 1; }

# Fast-forward idle local integration refs (test/main). Never switches branches.
_sync_integration() {
  local repo="${1:-}"
  local script="$FLEET_ROOT/.jv/scripts/fleet-sync-integration.js"
  [ -f "$script" ] || return 0
  if [ -n "$repo" ]; then
    node "$script" --auto "$repo" >/dev/null || true
  else
    node "$script" --auto >/dev/null || true
  fi
}

case "$(uname -s 2>/dev/null)" in
  Linux | Darwin) : ;;
  *) die "must run in a POSIX shell (WSL, Linux, or macOS)" ;;
esac

# --- MCP env load (self-contained: bootstrap copies this file alone) ----------
# Prefer shared lib when running from a revkit checkout; else use embedded.
_load_mcp_lib() {
  local candidates=(
    "${REVEALUI_ROOT:-}/shell/lib/revealui-mcp-env.sh"
    "$HOME/revealfleet/revkit/shell/lib/revealui-mcp-env.sh"
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

# Integration base for new worktrees: origin/test when present, else origin/main.
# Owner hardline 2026-07-21: never inherit a feature-branch HEAD as the worktree parent.
_resolve_integration_ref() {
  local repo="$1"
  if [ -n "${RFG_WORKTREE_REF:-}" ]; then
    echo "$RFG_WORKTREE_REF"
    return 0
  fi
  if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
    if git -C "$repo" rev-parse --verify --quiet origin/test >/dev/null 2>&1; then
      echo "test"
      return 0
    fi
    if git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
      echo "main"
      return 0
    fi
  fi
  # revealui and most fleet product repos use test even before first fetch
  case "${repo##*/}" in
    revealui) echo "test"; return 0 ;;
  esac
  echo "main"
}

# If argv requests a worktree and no --ref/--worktree-ref is set, inject --ref <integration>.
# Grok defaults worktree base to the source checkout HEAD; that is wrong on feature branches.
_inject_worktree_ref() {
  if [ "${RFG_WORKTREE_REF_SKIP:-0}" = 1 ]; then
    RFG_GROK_ARGS=("$@")
    return 0
  fi

  local has_worktree=0 has_ref=0
  local -a out=()
  local arg next

  while [ "$#" -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in
      -w | --worktree)
        has_worktree=1
        out+=("$arg")
        # optional name: next token if not a flag
        if [ "$#" -gt 0 ]; then
          next="$1"
          case "$next" in
            -*) ;;
            *)
              out+=("$next")
              shift
              ;;
          esac
        fi
        ;;
      --worktree=* | -w=*)
        has_worktree=1
        out+=("$arg")
        ;;
      --ref | --worktree-ref)
        has_ref=1
        out+=("$arg")
        if [ "$#" -gt 0 ]; then
          out+=("$1")
          shift
        fi
        ;;
      --ref=* | --worktree-ref=*)
        has_ref=1
        out+=("$arg")
        ;;
      *)
        out+=("$arg")
        ;;
    esac
  done

  if [ "$has_worktree" -eq 1 ] && [ "$has_ref" -eq 0 ]; then
    local ref
    ref="$(_resolve_integration_ref "$target")"
    set -- --ref "$ref" "${out[@]}"
  else
    set -- "${out[@]}"
  fi

  # Export reconstructed argv via global array for the caller (bash cannot return arrays).
  RFG_GROK_ARGS=("$@")
}

list_repos() {
  local d
  for d in "$FLEET_ROOT"/*/ "$FLEET_ROOT"/.*/; do
    [ -e "${d}.git" ] || continue
    d="${d%/}"; echo "  ${d##*/}"
  done
}

# Resolve a fleet helper installed next to rfg.sh or still in the revkit tree.
_resolve_helper() {
  local name="$1"
  local d c
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for c in \
    "$d/$name" \
    "/usr/local/bin/$name" \
    "$HOME/.local/bin/$name" \
    "$HOME/revfleet/revkit/shell/bin/$name" \
    "${REVEALUI_ROOT:-}/shell/bin/$name"
  do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

_load_grok_attach_lib() {
  local here f
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for f in \
    "$(dirname "$here")/lib/revkit/grok-attach.sh" \
    "$here/../lib/grok-attach.sh" \
    "$HOME/revfleet/revkit/shell/lib/grok-attach.sh" \
    "${REVEALUI_ROOT:-}/shell/lib/grok-attach.sh" \
    "$HOME/.local/lib/revkit/grok-attach.sh"
  do
    if [ -n "$f" ] && [ -f "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 1
}

_load_worktree_env_lib() {
  local here d candidates f
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  candidates=(
    # Installed layout: /usr/local/bin/rfg.sh → /usr/local/lib/revkit/worktree-env.sh
    "$(dirname "$here")/lib/revkit/worktree-env.sh"
    # Source layout: shell/bin/rfg.sh → shell/lib/worktree-env.sh
    "$here/../lib/worktree-env.sh"
    "$HOME/revfleet/revkit/shell/lib/worktree-env.sh"
    "${REVEALUI_ROOT:-}/shell/lib/worktree-env.sh"
    "$HOME/.local/lib/revkit/worktree-env.sh"
  )
  for f in "${candidates[@]}"; do
    if [ -n "$f" ] && [ -f "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 1
}

cmd="${1:-}"
case "$cmd" in
  mint)
    shift || true
    helper="$(_resolve_helper revealui-mcp-mint.sh)" || die "revealui-mcp-mint.sh not installed (re-run revkit bootstrap)"
    exec "$helper" "$@"
    ;;
  smoke)
    shift || true
    helper="$(_resolve_helper revealui-mcp-smoke.sh)" || die "revealui-mcp-smoke.sh not installed (re-run revkit bootstrap)"
    exec "$helper" "$@"
    ;;
  env)
    # Load to validate the vault, then drop the token before any print.
    # Printing REVEALUI_MCP_TOKEN is stdout secret-exfil (history, tmux, agents).
    REVEALUI_MCP_ENV_STRICT=1
    export REVEALUI_MCP_ENV_STRICT
    _revealui_mcp_env_load || exit 1
    unset REVEALUI_MCP_TOKEN
    printf 'export REVEALUI_MCP_URL=%q\n' "$REVEALUI_MCP_URL"
    printf 'export REVEALUI_MCP_TOKEN_VAULT_PATH=%q\n' "$REVEALUI_MCP_TOKEN_VAULT_PATH"
    echo "rfg env: token not printed. Load MCP with rfg <repo>, rfg mint, or rfg smoke." >&2
    exit 0
    ;;
  bootstrap)
    shift || true
    _load_worktree_env_lib || die "worktree-env.sh not found (re-run revkit bootstrap)"
    path="${1:-$PWD}"
    label="${2:-}"
    envf="$(rfg_write_worktree_env "$path" "$label")"
    echo "rfg: wrote $envf"
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1090
    . "$envf"
    set +a
    echo "rfg: RFG_PORT_BASE=${RFG_PORT_BASE:-?} MARKETING_PORT=${MARKETING_PORT:-?} API_PORT=${API_PORT:-?}"
    exit 0
    ;;
  claim)
    shift || true
    _load_worktree_env_lib || die "worktree-env.sh not found (re-run revkit bootstrap)"
    sub="${1:-list}"
    shift || true
    case "$sub" in
      acquire | take)
        repo="${1:-}"; surface="${2:-}"; ttl="${3:-24}"
        [ -n "$repo" ] && [ -n "$surface" ] || die "usage: rfg claim acquire <repo> <surface> [ttl_hours]"
        rfg_claim_acquire "$repo" "$surface" "$ttl"
        ;;
      release | drop)
        repo="${1:-}"; surface="${2:-}"
        [ -n "$repo" ] && [ -n "$surface" ] || die "usage: rfg claim release <repo> <surface>"
        rfg_claim_release "$repo" "$surface"
        ;;
      list)
        rfg_claim_list "${1:-}"
        ;;
      check)
        repo="${1:-}"; surface="${2:-}"
        [ -n "$repo" ] && [ -n "$surface" ] || die "usage: rfg claim check <repo> <surface>"
        rfg_claim_check "$repo" "$surface"
        ;;
      sweep)
        rfg_claim_sweep
        ;;
      *)
        die "usage: rfg claim acquire|release|list|check|sweep …"
        ;;
    esac
    exit 0
    ;;
  open)
    # rfg open <repo> <label> [--claim surface] [--no-agent] [extra grok args…]
    shift || true
    _load_worktree_env_lib || die "worktree-env.sh not found (re-run revkit bootstrap)"
    open_repo="${1:-}"
    open_label="${2:-}"
    [ -n "$open_repo" ] && [ -n "$open_label" ] || die "usage: rfg open <repo> <label> [--claim surface] [--no-agent] [grok-args…]"
    shift 2 || true
    claim_surface=""
    no_agent=0
    open_extra=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --claim)
          claim_surface="${2:-}"
          [ -n "$claim_surface" ] || die "--claim requires a surface id"
          shift 2
          ;;
        --claim=*)
          claim_surface="${1#--claim=}"
          shift
          ;;
        --no-agent)
          no_agent=1
          shift
          ;;
        *)
          open_extra+=("$1")
          shift
          ;;
      esac
    done

    source_repo="$FLEET_ROOT/$open_repo"
    [ -d "$source_repo" ] || die "no such fleet repo: $open_repo"
    wt_root="${RFG_WT_ROOT:-$HOME/revfleet/.wt}"
    wt_path="$wt_root/$open_label"
    ref="$(_resolve_integration_ref "$source_repo")"

    if [ -e "$wt_path" ]; then
      echo "rfg: worktree path exists: $wt_path (bootstrap only)" >&2
    else
      mkdir -p "$wt_root"
      echo "rfg: syncing origin/$ref …" >&2
      _sync_integration "$source_repo"
      git -C "$source_repo" fetch origin "$ref" 2>/dev/null || git -C "$source_repo" fetch origin || true
      base="origin/$ref"
      if ! git -C "$source_repo" rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
        base="$ref"
      fi
      branch="feat/${open_label}"
      # If branch exists, attach worktree to it; else create.
      if git -C "$source_repo" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$source_repo" worktree add "$wt_path" "$branch"
      else
        git -C "$source_repo" worktree add -b "$branch" "$wt_path" "$base"
      fi
      echo "rfg: created $wt_path ($branch from $base)" >&2
    fi

    envf="$(rfg_write_worktree_env "$wt_path" "$open_label")"
    echo "rfg: bootstrap $envf" >&2

    if [ -n "$claim_surface" ]; then
      RFG_CLAIM_WORKTREE="$wt_path"
      RFG_CLAIM_AGENT="${RFG_CLAIM_AGENT:-grok}"
      export RFG_CLAIM_WORKTREE RFG_CLAIM_AGENT
      claim_file="$(rfg_claim_acquire "$open_repo" "$claim_surface")" || die "claim failed for $claim_surface"
      echo "rfg: claimed $claim_file" >&2
    fi

    if [ "$no_agent" -eq 1 ]; then
      echo "$wt_path"
      exit 0
    fi

    grok_bin="$(resolve_grok)" || die "grok not found on PATH or in ~/.grok/bin / ~/.local/bin"
    load_mcp_strict || die "MCP env not ready (mint with: rfg mint)"
    cd "$wt_path"
    _load_grok_attach_lib && rfg_attach_grok_constitution && rfg_attach_grok_hooks "$wt_path"
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1090
    . "$envf"
    set +a
    exec "$grok_bin" "${open_extra[@]}"
    ;;
  -h | --help | help)
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

repo="${1:-}"
if [ -n "${repo:-}" ]; then
  shift
fi

if [ -z "${repo:-}" ]; then
  if rfg_path_is_in_fleet "$FLEET_ROOT" "$PWD"; then
    target="$PWD"
  else
    echo "rfg: name a fleet repo, e.g. 'rfg revealui'. Available:" >&2
    list_repos >&2
    exit 2
  fi
else
  case "$repo" in
    -*)
      if rfg_path_is_in_fleet "$FLEET_ROOT" "$PWD"; then
        target="$PWD"
        set -- "$repo" "$@"
      else
        die "name a fleet repo before grok flags, or cd into the fleet root / a repo"
      fi
      ;;
    *)
      target="$FLEET_ROOT/$repo"
      [ -d "$target" ] || die "no such fleet repo: '$repo' (under $FLEET_ROOT)"
      ;;
  esac
fi

_load_grok_attach_lib || die "grok-attach.sh not found (re-run revkit bootstrap)"

grok_bin="$(resolve_grok)" || die "grok not found on PATH or in ~/.grok/bin / ~/.local/bin"

_sync_integration "$target"

load_mcp_strict || die "MCP env not ready (mint with: rfg mint)"

RFG_GROK_ARGS=("$@")
_inject_worktree_ref "$@"
set -- "${RFG_GROK_ARGS[@]}"

cd "$target"
_load_grok_attach_lib && rfg_attach_grok_constitution && rfg_attach_grok_hooks "$target"
exec "$grok_bin" "$@"
