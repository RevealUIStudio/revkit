#!/usr/bin/env bash
# revealui — retired PATH name (GAP-351).
#
# The untracked ~/.local/bin/revealui was a tmux workspace launcher aimed at
# ~/projects. Agent sessions do not persist in a multiplexer (ADR
# 2026-06-23-drop-tmux-agent-terminals). Durable start:
#   rfg <repo>   Grok + RevealUI MCP
#   rfc <repo>   Claude in a fleet repo
# Resume is the harness + Windows Terminal / RevDev Studio, not tmux panes.
#
# bootstrap.sh installs this file as ~/.local/bin/revealui (overwriting the
# old launcher) and as revealui.sh next to rfc.sh / rfg.sh.

set -euo pipefail

cat >&2 <<'EOF'
revealui: retired. Do not start a multiplexer.

  Grok:   rfg <repo>
  Claude: rfc <repo>

Session resume is the harness (rfg / rfc / RevDev Studio), not tmux.
EOF
exit 2
