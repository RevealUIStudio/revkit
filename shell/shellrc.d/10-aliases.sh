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
