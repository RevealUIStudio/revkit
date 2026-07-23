# shellcheck shell=bash
# RevealUI Studio / RevFleet project aliases and shortcuts
#
# Naming: RevealUI = product monorepo; RevealUI Studio = company; RevFleet = umbrella.
# Coordination: TRACKER (free surfaces), workboard (.jv), base origin/test, PR→test.

# Quick project navigation
# cdreveal → primary RevealUI checkout (WSL-native ext4 at ~/revfleet/revealui).
# The legacy /mnt/sandbox/repos/RevealUI-Suite target was retired with the
# Suite→RevFleet rename, and the sandbox drive is no longer a dev-infra target;
# the old alias also reported every failure as "drive not mounted", masking a
# simply-missing checkout. The message now names the actual missing path.
alias cdreveal='cd ~/revfleet/revealui 2>/dev/null || echo "cdreveal: RevealUI checkout not found at ~/revfleet/revealui" >&2'
alias cdjv='cd ~/revfleet/.jv 2>/dev/null || echo "cdjv: private planning not found at ~/revfleet/.jv" >&2'
alias cdfleet='cd ~/revfleet 2>/dev/null || echo "cdfleet: ~/revfleet not found" >&2'
alias cdprojects='cd ~/projects'

# Day-to-day free surfaces (fleet methodology). Same as Nix shell `tracker`.
tracker() {
  local t="${REVEALUI_TRACKER:-$HOME/revfleet/.jv/docs/TRACKER.md}"
  if [ ! -f "$t" ]; then
    echo "tracker: not found at $t" >&2
    return 1
  fi
  if [ "${1:-}" = "watch" ]; then
    watch -n5 "glow '$t' 2>/dev/null || cat '$t'"
  else
    command -v glow >/dev/null 2>&1 && glow "$t" || less -R "$t"
  fi
}

# Canonical workboard (not revealui/.claude/workboard.md stub)
wb() {
  local _wb="${REVEALUI_WORKBOARD:-$HOME/revfleet/.jv/.claude/workboard.md}"
  if [ ! -f "$_wb" ]; then
    echo "wb: workboard not found at $_wb" >&2
    return 1
  fi
  if [ "${1:-}" = "once" ]; then
    command -v glow >/dev/null 2>&1 && glow "$_wb" || cat "$_wb"
  else
    watch -n3 "glow '$_wb' 2>/dev/null || cat '$_wb'"
  fi
}
