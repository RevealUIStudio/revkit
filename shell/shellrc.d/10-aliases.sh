# shellcheck shell=bash
# RevealUI project aliases and shortcuts

# Quick project navigation
# cdreveal → primary RevealUI checkout (WSL-native ext4 at ~/revfleet/revealui).
# The legacy /mnt/sandbox/repos/RevealUI-Suite target was retired with the
# Suite→RevFleet rename, and the sandbox drive is no longer a dev-infra target;
# the old alias also reported every failure as "drive not mounted", masking a
# simply-missing checkout. The message now names the actual missing path.
alias cdreveal='cd ~/revfleet/revealui 2>/dev/null || echo "cdreveal: RevealUI checkout not found at ~/revfleet/revealui" >&2'
alias cdprojects='cd ~/projects'
