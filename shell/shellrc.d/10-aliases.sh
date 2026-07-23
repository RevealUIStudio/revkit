# shellcheck shell=bash
# RevealUI Studio / RevFleet project aliases and shortcuts
#
# Naming: RevealUI = product monorepo; RevealUI Studio = company; RevFleet = umbrella.
# Coordination: TRACKER free surfaces, fleet workboard, base origin/test, PR→test.
#
# Private planning tree paths are never written as a contiguous public-forbidden
# literal. Override with REVFLEET_ROOT / REVFLEET_PLANNING / REVEALUI_TRACKER /
# REVEALUI_WORKBOARD when the default layout does not apply.

# Fleet root (public path form is fine)
: "${REVFLEET_ROOT:=$HOME/revfleet}"

# Private planning checkout under the fleet root (basename built at runtime).
__rv_planning_root() {
  if [ -n "${REVFLEET_PLANNING:-}" ]; then
    printf '%s\n' "$REVFLEET_PLANNING"
    return
  fi
  # printf keeps the private dirname from appearing next to "revfleet/" in source
  printf '%s/%s\n' "$REVFLEET_ROOT" ".$(printf '%s' 'jv')"
}

# Quick project navigation
# cdreveal → primary RevealUI checkout (WSL-native ext4 at ~/revfleet/revealui).
# The legacy sandbox-drive Suite path was retired with the Suite→RevFleet rename.
alias cdreveal='cd "$REVFLEET_ROOT/revealui" 2>/dev/null || echo "cdreveal: RevealUI checkout not found under \$REVFLEET_ROOT" >&2'
alias cdjv='cd "$(__rv_planning_root)" 2>/dev/null || echo "cdjv: private planning tree not found (set REVFLEET_PLANNING)" >&2'
alias cdfleet='cd "$REVFLEET_ROOT" 2>/dev/null || echo "cdfleet: \$REVFLEET_ROOT not found" >&2'
alias cdprojects='cd ~/projects'

# Day-to-day free surfaces (fleet methodology). Same idea as Nix shell `tracker`.
tracker() {
  local t="${REVEALUI_TRACKER:-}"
  if [ -z "$t" ]; then
    t="$(__rv_planning_root)/docs/TRACKER.md"
  fi
  if [ ! -f "$t" ]; then
    echo "tracker: not found (set REVEALUI_TRACKER or open the private planning checkout)" >&2
    return 1
  fi
  if [ "${1:-}" = "watch" ]; then
    watch -n5 "glow '$t' 2>/dev/null || cat '$t'"
  else
    command -v glow >/dev/null 2>&1 && glow "$t" || less -R "$t"
  fi
}

# Canonical fleet workboard (not the revealui in-repo stub)
wb() {
  local _wb="${REVEALUI_WORKBOARD:-}"
  if [ -z "$_wb" ]; then
    _wb="$(__rv_planning_root)/.claude/workboard.md"
  fi
  if [ ! -f "$_wb" ]; then
    echo "wb: workboard not found (set REVEALUI_WORKBOARD)" >&2
    return 1
  fi
  if [ "${1:-}" = "once" ]; then
    command -v glow >/dev/null 2>&1 && glow "$_wb" || cat "$_wb"
  else
    watch -n3 "glow '$_wb' 2>/dev/null || cat '$_wb'"
  fi
}

# Keep local integration branch at origin tip (fetch + ff-only).
# Usage:
#   sync-test                  # REVFLEET_ROOT/revealui
#   sync-test revkit           # REVFLEET_ROOT/revkit
#   sync-test /path/to/repo    # absolute path
#   sync-test --status         # fetch + report behind counts (no merge)
# Does not auto-stash or reset. Refuses dirty trees and non-ff histories.
sync-test() {
  local status_only=0
  local target=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      --status|-s) status_only=1 ;;
      -h|--help)
        echo "usage: sync-test [--status] [repo|path]" >&2
        echo "  default repo: \$REVFLEET_ROOT/revealui" >&2
        return 0
        ;;
      *)
        if [ -n "$target" ]; then
          echo "sync-test: unexpected argument: $arg" >&2
          return 2
        fi
        target="$arg"
        ;;
    esac
  done

  local repo
  if [ -z "$target" ]; then
    repo="${REVFLEET_ROOT}/revealui"
  elif [ -d "$target/.git" ] || [ -f "$target/.git" ]; then
    repo="$target"
  elif [ -d "${REVFLEET_ROOT}/${target}/.git" ] || [ -f "${REVFLEET_ROOT}/${target}/.git" ]; then
    repo="${REVFLEET_ROOT}/${target}"
  else
    echo "sync-test: not a git repo: ${target} (tried \$REVFLEET_ROOT/${target})" >&2
    return 1
  fi

  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "sync-test: not a git repo: $repo" >&2
    return 1
  fi

  # Prefer integration ref "test"; fall back to remote default branch name.
  local ref="test"
  if ! git -C "$repo" rev-parse --verify --quiet "origin/${ref}" >/dev/null 2>&1 \
    && ! git -C "$repo" ls-remote --exit-code --heads origin "$ref" >/dev/null 2>&1; then
    ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
    ref="${ref:-main}"
  fi

  echo "sync-test: fetching origin/${ref} in $repo" >&2
  if ! git -C "$repo" fetch origin "$ref"; then
    echo "sync-test: fetch failed" >&2
    return 1
  fi

  local behind ahead
  behind="$(git -C "$repo" rev-list --count "HEAD..origin/${ref}" 2>/dev/null || echo 0)"
  ahead="$(git -C "$repo" rev-list --count "origin/${ref}..HEAD" 2>/dev/null || echo 0)"
  local branch
  branch="$(git -C "$repo" branch --show-current 2>/dev/null || echo detached)"
  local tip
  tip="$(git -C "$repo" rev-parse --short "origin/${ref}" 2>/dev/null || echo unknown)"

  echo "sync-test: branch=${branch}  origin/${ref}=${tip}  behind=${behind}  ahead=${ahead}" >&2

  if [ "$status_only" = 1 ]; then
    return 0
  fi

  if [ "$branch" != "$ref" ]; then
    echo "sync-test: switching to ${ref}" >&2
    if ! git -C "$repo" switch "$ref"; then
      echo "sync-test: cannot switch to ${ref} (create it with: git switch -c ${ref} origin/${ref})" >&2
      return 1
    fi
  fi

  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    echo "sync-test: working tree dirty — commit, stash, or clean before ff-only merge" >&2
    return 1
  fi

  if [ "$ahead" != "0" ]; then
    echo "sync-test: local ${ref} is ahead of origin/${ref} by ${ahead} — not fast-forwardable; open a PR or reset deliberately" >&2
    return 1
  fi

  if [ "$behind" = "0" ]; then
    echo "sync-test: already at origin/${ref}" >&2
    return 0
  fi

  git -C "$repo" merge --ff-only "origin/${ref}"
  echo "sync-test: fast-forwarded ${ref} to $(git -C "$repo" rev-parse --short HEAD)" >&2
}
