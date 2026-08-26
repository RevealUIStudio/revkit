# shellcheck shell=bash
# grok-attach.sh — deploy Grok vendor attach points from RevKit + product manager.
#
# Grok CLI always loads $GROK_HOME (default ~/.grok): hooks, rules, AGENTS.md.
# That path is a vendor cache, not an authoring surface.
# SSOT:
#   hooks      <repo>/.revealui/adapters/grok/hooks/*.json
#   HOME rules revkit/shell/grok-home/ (AGENTS.md + 00-09 pointers)
# Product preamble is <repo>/.grok/rules/ (loaded when cwd is the product).
# RevKit (rfg + bootstrap) copies allowlisted files to the attach point.
#
# Skip: RFG_GROK_ATTACH_SKIP=1

rfg_grok_home() {
  printf '%s\n' "${GROK_HOME:-$HOME/.grok}"
}

# RevKit templates for Grok HOME constitution (AGENTS.md + 00-09 pointers).
rfg_grok_home_src() {
  local here f
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for f in \
    "$here/../grok-home" \
    "$here/grok-home" \
    "$HOME/revfleet/revkit/shell/grok-home"
  do
    if [ -n "$f" ] && [ -d "$f/rules" ] && [ -f "$f/AGENTS.md" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

# Copy allowlisted HOME constitution onto Grok's vendor attach.
rfg_attach_grok_constitution() {
  local src dest f name
  [ "${RFG_GROK_ATTACH_SKIP:-0}" = "1" ] && return 0
  src="$(rfg_grok_home_src)" || return 0
  dest="$(rfg_grok_home)"
  mkdir -p "$dest/rules"
  if [ ! -f "$dest/AGENTS.md" ] || ! cmp -s "$src/AGENTS.md" "$dest/AGENTS.md"; then
    cp "$src/AGENTS.md" "$dest/AGENTS.md"
  fi
  for f in "$src/rules"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in
      00-dual-harness.md | 01-fleet-map.md | 02-dispositions.md | 03-git-and-branches.md | 04-subagents-and-tokens.md | 05-secrets-and-safety.md | 06-worktree-isolation.md | 07-durable-solutions.md | 08-model-allocation.md | 09-unused-no-underscore.md) ;;
      *) continue ;;
    esac
    if [ ! -f "$dest/rules/$name" ] || ! cmp -s "$f" "$dest/rules/$name"; then
      cp "$f" "$dest/rules/$name"
    fi
  done
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

# Copy allowlisted hook JSON from a product checkout into the Grok attach dir.
# No-op when the manager templates are absent (revkit, .jv, …).
rfg_attach_grok_hooks() {
  local root="${1:-}"
  local src dest f name
  [ "${RFG_GROK_ATTACH_SKIP:-0}" = "1" ] && return 0
  [ -n "$root" ] || return 0
  src="$root/.revealui/adapters/grok/hooks"
  [ -d "$src" ] || return 0
  dest="$(rfg_grok_home)/hooks"
  mkdir -p "$dest"
  for f in "$src"/*.json; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in
      session-start.json | session-end.json | pre-tool.json) ;;
      *) continue ;;
    esac
    if [ ! -f "$dest/$name" ] || ! cmp -s "$f" "$dest/$name"; then
      cp "$f" "$dest/$name"
    fi
  done

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
