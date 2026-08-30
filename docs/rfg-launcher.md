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
| Worktree ports + claims | **RevKit** | `shell/lib/worktree-env.sh` (Rift-inspired; used by `rfg bootstrap|claim|open`) |
| Shell aliases | **RevKit** | `shell/shellrc.d/55-rfg.sh` → `rfg`, `rfgrok`, `grok-rv` |
| MCP server config | **Repo** | `<repo>/.grok/config.toml` `[mcp_servers.revealui]` env refs only |
| Secret | **RevVault** | `revealui/dev/mcp/cli-token` |
| Global Grok prefs | User home | `~/.grok/config.toml` (permissions/UI only) |
| Grok HOME stub | **RevKit `rfg` / bootstrap** | Copies `shell/grok-home/AGENTS.md` onto `$GROK_HOME`. No prose rules in HOME. |
| Grok vendor hooks | **RevKit `rfg` / bootstrap** | Copies `<repo>/.revealui/adapters/grok/hooks/*.json` onto `$GROK_HOME/hooks`. Mechanical deny. |
| Product Grok constitution | **Repo** | `<repo>/.grok/rules/` (harnesses materialize). Loaded when cwd is the product. |

**Not durable:** one-off eval lines, secrets in chat, home-only mint scripts, operator `cp` of policy into `$HOME/.grok`, hand-edits of `$HOME/.grok/AGENTS.md` or `$HOME/.grok/rules/`.

`rfg env` prints only `REVEALUI_MCP_URL` and `REVEALUI_MCP_TOKEN_VAULT_PATH`.
It never prints `REVEALUI_MCP_TOKEN`. Do not eval a printed token — there
is none. Load MCP by running `rfg <repo>` (or `rfg mint` then `rfg smoke`).
Non-rfg tools should source `shell/lib/revealui-mcp-env.sh` and call
`_revealui_mcp_env_load` in-process, or read the vault path with revvault.

## Usage

```bash
rfg revealui          # load token + cd + exec grok (product session)
rfg                   # already *inside* ~/revfleet/<repo> (not fleet root)
# Fleet root is not a product session — rfg / rfg . there exits 2.
# Skip Grok vendor-hook attach: RFG_GROK_ATTACH_SKIP=1

# The PATH name `revealui` was a tmux workspace launcher. It is retired
# (GAP-351). `bootstrap.sh` overwrites ~/.local/bin/revealui with a shim.
rfg smoke             # auth + MCP health (no secret print)
rfg mint              # OTP → revvault
rfg env               # non-secret URL + vault path only (never the token)

# Worktrees (owner hardline 2026-07-21: never inherit a feature-branch HEAD)
rfg revealui --worktree=fix-gap-xxx "…"
# → rfg injects `--ref test` when you omit --ref / --worktree-ref
# Prefer origin/test when present, else origin/main. Override with RFG_WORKTREE_REF=…
# Disable inject: RFG_WORKTREE_REF_SKIP=1

Before launch and worktree create, `rfg` runs the fleet integration-ref
sync (`sync-test` / `fleet-sync-integration --auto`) so the local
integration branch (`test` or `main`) is not left behind origin. That
script never switches the current branch. SessionStart (Claude + Grok)
runs the same tool across the fleet.

# Rift-inspired isolation (runtime ports + claim registry)
rfg open revealui ves-fo-managed --claim marketing/ves-fo-managed
# → git worktree at ~/revfleet/.wt/ves-fo-managed from origin/test
# → writes .env.worktree (hash ports 3000–9999 + multi-service offsets)
# → PID/TTL claim under ~/.local/share/revealui/claims/
# → exec grok with MCP env (use --no-agent to stop after bootstrap)

rfg bootstrap ~/revfleet/.wt/ves-fo-managed   # ports only
rfg claim acquire revealui marketing/ves-fo-managed
rfg claim list
rfg claim release revealui marketing/ves-fo-managed
rfg claim sweep
```

### Worktree ports (Rift-inspired)

Same worktree **name** always gets the same base port:

```text
BASE = (sha1(name) % 7000) + 3000
MARKETING/VITE/PORT = BASE
ADMIN = BASE+1
DOCS = BASE+2
API/SERVER = BASE+3
PREVIEW = BASE+4
ELECTRIC = BASE+5
```

Files:

| Path | Role |
|------|------|
| `<worktree>/.env.worktree` | local runtime (do **not** commit) |
| `~/.local/share/revealui/worktree-env/<project>/<label>.env` | mirror |

Add `.env.worktree` to product repo `.gitignore` once (rfg does not mutate gitignore).

### Claims (PID + TTL)

| Path | Role |
|------|------|
| `~/.local/share/revealui/claims/<repo>/<surface>.json` | active lease |

A claim is **active** if the recorded PID is alive **or** `expiresAt` is still in the future. Stale files are removable via `rfg claim sweep`.

Claims coordinate agents; they do **not** replace modular product code (e.g. revealui `page-blocks/pages/*`). Isolation at the worktree layer cannot prevent merge conflicts on a shared mega-file.

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
| `RFG_WT_ROOT` | `$HOME/revfleet/.wt` |
| `REVEALUI_CLAIMS_DIR` | `$HOME/.local/share/revealui/claims` |
| `REVEALUI_WT_ENV_DIR` | `$HOME/.local/share/revealui/worktree-env` |
| `RFG_CLAIM_FORCE=1` | steal an active claim |
| `RFG_CLAIM_AGENT` | agent label written into claim JSON |
