# `rfg` — RevFleet Grok launcher (durable)

`rfg` is the **only supported** way to start Grok against the fleet with
RevealUI MCP attached. It is the Grok sibling of `rfc` (Claude).

No manual `eval`, no home-directory scripts as source of truth.

**Project manager** = `./.revealui` (`manager.json` + content; equal vendor adapters).

## Contract (long-term)

| Piece | Owner | Durable location |
|-------|-------|------------------|
| Launcher | **RevKit** | `shell/bin/rfg.sh` |
| Mint / smoke | **RevKit** | `shell/bin/revealui-mcp-{mint,smoke}.sh` |
| Env loader | **RevKit** | `shell/lib/revealui-mcp-env.sh` (+ embedded fallback in `rfg.sh`) |
| Shell aliases | **RevKit** | `shell/shellrc.d/55-rfg.sh` → `rfg`, `rfgrok`, `grok-rv` |
| MCP server config | **Repo** | `<repo>/.grok/config.toml` `[mcp_servers.revealui]` env refs only |
| Secret | **RevVault** | `revealui/dev/mcp/cli-token` |
| Global Grok prefs | User home | `~/.grok/config.toml` (permissions/UI only; optional MCP duplicate) |

**Not durable:** one-off `eval "$(…)"` lines, secrets in chat, home-only mint scripts as the canonical path.

## Usage

```bash
rfg revealui          # load token + cd + exec grok
rfg                   # already under ~/revfleet/<repo>
rfg smoke             # auth + MCP health (no secret print)
rfg mint              # OTP → revvault
eval "$(rfg env)"     # rare: export for non-rfg tools

# Worktrees (owner hardline 2026-07-21: never inherit a feature-branch HEAD)
rfg revealui --worktree=fix-gap-xxx "…"
# → rfg injects `--ref test` when you omit --ref / --worktree-ref
# Prefer origin/test when present, else origin/main. Override with RFG_WORKTREE_REF=…
# Disable inject: RFG_WORKTREE_REF_SKIP=1
```

## Install

Bootstrap deploys all `shell/bin/*.sh` (including `rfg` helpers):

```bash
cd ~/revfleet/revkit && bash bootstrap.sh
source ~/.bashrc
```

Or symlink until bootstrap:

```bash
ln -sfn ~/revfleet/revkit/shell/bin/rfg.sh ~/.local/bin/rfg.sh
ln -sfn ~/revfleet/revkit/shell/bin/rfg.sh ~/.local/bin/rfg
ln -sfn ~/revfleet/revkit/shell/bin/revealui-mcp-mint.sh ~/.local/bin/revealui-mcp-mint.sh
ln -sfn ~/revfleet/revkit/shell/bin/revealui-mcp-smoke.sh ~/.local/bin/revealui-mcp-smoke.sh
source ~/revfleet/revkit/shell/shellrc.d/55-rfg.sh
```

## RevCon / RevSkills

| Product | Durable role |
|---------|----------------|
| **RevKit** | Runtime entrypoint + secrets load |
| **RevCon** | Editor/agent *content* generators only — does not own shell launch |
| **RevSkills** | Skills document `rfg`; no second secret store |

Future Level 2 (`GrokAdapter` in `@revealui/harnesses`) extends the same data plane; it does not replace `rfg` for interactive Grok.

## Env overrides

| Variable | Default |
|----------|---------|
| `REVFLEET_ROOT` | `$HOME/revfleet` |
| `REVEALUI_MCP_URL` | `https://api.revealui.com/api/mcp` |
| `REVEALUI_MCP_TOKEN_VAULT_PATH` | `revealui/dev/mcp/cli-token` |
| `REVEALUI_MCP_ENV_SKIP=1` | skip vault (debug) |
| `RFG_WORKTREE_REF` | auto: `test` if `origin/test` else `main` |
| `RFG_WORKTREE_REF_SKIP=1` | do not inject `--ref` on `--worktree` |
