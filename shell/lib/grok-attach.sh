# shellcheck shell=bash
# grok-attach.sh — deploy Grok vendor attach points from RevKit + product manager.
#
# $GROK_HOME (default ~/.grok) is a vendor cache: auth, UI, hooks, stub AGENTS.md.
# It is not a policy SSOT. Constitution lives in the product tree:
#   hooks      <repo>/.revealui/adapters/grok/hooks/*.json
#   preamble   <repo>/.grok/rules/ (harnesses materialize)
# HOME gets only a pointer stub (shell/grok-home/AGENTS.md) plus hook JSON.
#
# Skip: RFG_GROK_ATTACH_SKIP=1

rfg_grok_home() {
  printf '%s\n' "${GROK_HOME:-$HOME/.grok}"
}

rfg_grok_home_src() {
  local here f
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for f in \
    "$here/../grok-home" \
    "$here/grok-home" \
    "${REVEALUI_ROOT:-}/shell/grok-home"
  do
    if [ -n "$f" ] && [ -f "$f/AGENTS.md" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

# Copy the public stub AGENTS.md only. Never copy prose rules into HOME.
rfg_attach_grok_constitution() {
  local src dest
  [ "${RFG_GROK_ATTACH_SKIP:-0}" = "1" ] && return 0
  src="$(rfg_grok_home_src)" || return 0
  dest="$(rfg_grok_home)"
  mkdir -p "$dest"
  if [ ! -f "$dest/AGENTS.md" ] || ! cmp -s "$src/AGENTS.md" "$dest/AGENTS.md"; then
    cp "$src/AGENTS.md" "$dest/AGENTS.md"
  fi
}

# True when path is exactly the fleet root (not a product repo under it).
rfg_path_is_fleet_root() {
  local fleet="${1:-}"
  local path="${2:-}"
  local fleet_real path_real
  [ -n "$fleet" ] && [ -n "$path" ] || return 1
  if [ -d "$fleet" ]; then
    fleet_real="$(cd "$fleet" && pwd -P)"
  else
    return 1
  fi
  if [ -d "$path" ]; then
    path_real="$(cd "$path" && pwd -P)"
  else
    return 1
  fi
  [ "$path_real" = "$fleet_real" ]
}

rfg_pwd_is_fleet_root() {
  rfg_path_is_fleet_root "${1:-}" "$(pwd -P 2>/dev/null || pwd)"
}

# Fleet root that contains revskills, when this product checkout sits inside one.
rfg_fleet_root_of() {
  local root="${1:-}"
  local parent fleet
  [ -n "$root" ] || return 1
  if [ -n "${REVEALFLEET_ROOT:-}" ] && [ -d "${REVEALFLEET_ROOT}/revskills/scripts" ]; then
    printf '%s\n' "$REVEALFLEET_ROOT"
    return 0
  fi
  parent="$(cd "$root/.." 2>/dev/null && pwd)" || return 1
  if [ -d "$parent/revskills/scripts" ] && [ -d "$parent/revealui" ]; then
    printf '%s\n' "$parent"
    return 0
  fi
  fleet="${HOME}/revealfleet"
  if [ -d "$fleet/revskills/scripts" ]; then
    printf '%s\n' "$fleet"
    return 0
  fi
  return 1
}

# Install the one revskills implementation of the output cap and the budget reader.
rfg_install_grok_budget_scripts() {
  local root="${1:-}"
  local fleet src dest name
  fleet="$(rfg_fleet_root_of "$root" 2>/dev/null || true)"
  [ -n "$fleet" ] || return 0
  dest="$HOME/.local/share/revealui/hooks"
  mkdir -p "$dest"
  for name in cap-tool-output.js snapshot-before-compact.js sync-grok-token-budget.js; do
    src="$fleet/revskills/scripts/$name"
    [ -f "$src" ] || continue
    if [ ! -f "$dest/$name" ] || ! cmp -s "$src" "$dest/$name"; then
      cp "$src" "$dest/$name"
    fi
  done
  src="$fleet/revskills/scripts/lib/read-token-budget.js"
  if [ -f "$src" ]; then
    if [ ! -f "$dest/read-token-budget.js" ] || ! cmp -s "$src" "$dest/read-token-budget.js"; then
      cp "$src" "$dest/read-token-budget.js"
    fi
  fi
}

# Apply token-budget.json onto the Grok user config. No-op without the file.
rfg_sync_grok_token_budget() {
  local root="${1:-}"
  local budget sync dest
  [ -n "$root" ] || return 0
  budget="$root/.revealui/adapters/grok/token-budget.json"
  [ -f "$budget" ] || return 0
  sync="$HOME/.local/share/revealui/hooks/sync-grok-token-budget.js"
  if [ ! -f "$sync" ]; then
    local fleet
    fleet="$(rfg_fleet_root_of "$root" 2>/dev/null || true)"
    if [ -n "$fleet" ] && [ -f "$fleet/revskills/scripts/sync-grok-token-budget.js" ]; then
      sync="$fleet/revskills/scripts/sync-grok-token-budget.js"
    fi
  fi
  [ -f "$sync" ] || return 0
  dest="$(rfg_grok_home)/config.toml"
  mkdir -p "$(dirname "$dest")"
  node "$sync" "$budget" "$dest"
}

# Copy allowlisted hook JSON from a product checkout into the Grok attach dir.
# No-op when the manager templates are absent (revkit, .jv, …).
rfg_attach_grok_hooks() {
  local root="${1:-}"
  local src dest f name
  [ "${RFG_GROK_ATTACH_SKIP:-0}" = "1" ] && return 0
  [ -n "$root" ] || return 0
  rfg_install_grok_budget_scripts "$root"
  src="$root/.revealui/adapters/grok/hooks"
  if [ -d "$src" ]; then
    dest="$(rfg_grok_home)/hooks"
    mkdir -p "$dest"
    for f in "$src"/*.json; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"
      case "$name" in
        session-start.json | session-end.json | pre-tool.json | cap-tool-output.json | nonukes.json | dirty-checkout.json) ;;
        *) continue ;;
      esac
      if [ ! -f "$dest/$name" ] || ! cmp -s "$f" "$dest/$name"; then
        cp "$f" "$dest/$name"
      fi
    done
  fi

  # Budget the cap script and the snapshot gate both read.
  local budget_src budget_dest
  budget_src="$root/.revealui/adapters/grok/token-budget.json"
  if [ -f "$budget_src" ]; then
    budget_dest="$HOME/.local/share/revealui/hooks/token-budget.json"
    mkdir -p "$(dirname "$budget_dest")"
    if [ ! -f "$budget_dest" ] || ! cmp -s "$budget_src" "$budget_dest"; then
      cp "$budget_src" "$budget_dest"
    fi
  fi
  rfg_sync_grok_token_budget "$root"

  # PreToolUse helper: hook JSON runs this path. Deploy from the product tree.
  local helper_src helper_dest
  helper_src="$root/packages/harnesses/scripts/public-security-comment-pretool.cjs"
  if [ -f "$helper_src" ]; then
    helper_dest="$HOME/.local/share/revealui/hooks/public-security-comment-pretool.cjs"
    mkdir -p "$(dirname "$helper_dest")"
    if [ ! -f "$helper_dest" ] || ! cmp -s "$helper_src" "$helper_dest"; then
      cp "$helper_src" "$helper_dest"
    fi
  fi
}
