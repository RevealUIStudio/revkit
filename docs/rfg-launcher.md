# `rfg` — RevFleet Grok launcher (MCP attach built in)

`rfg` starts a **Grok** session rooted in a RevFleet repo with the Level 1
RevealUI MCP environment already loaded from **revvault**. You should not need
to run `eval "$(…/revealui-mcp-env)"` by hand.

Sibling of [`rfc`](./rfc-launcher.md) (Claude). Same fleet-root resolution.

## Why this exists

Grok’s MCP client expands `${REVEALUI_MCP_TOKEN}` from the process environment
at load time (`~/.grok/config.toml` → `[mcp_servers.revealui]`). If you launch
`grok` without that env, the RevealUI server never authenticates.

`rfg` loads the token from the canonical vault path and then `exec`s Grok.

## Usage

```bash
rfg                  # use $PWD if under ~/revfleet, else list repos
rfg revealui         # cd ~/revfleet/revealui && load MCP env && exec grok
rfg revealui --help  # trailing args pass through to grok
rfg mint             # OTP device-token mint → revvault
rfg smoke            # auth/MCP health check (no secret print)
eval "$(rfg env)"    # export only (rare; for non-rfg tools)
```

Aliases (interactive shells via `shellrc.d/55-rfg.sh`):

| Alias | Same as |
|-------|---------|
| `rfgrok` | `rfg` |
| `grok-rv` | `rfg` |

## Secrets

| Item | Location |
|------|----------|
| Device token | revvault `revealui/dev/mcp/cli-token` |
| Grok MCP config | `~/.grok/config.toml` — `Bearer ${REVEALUI_MCP_TOKEN}` only |
| Loader | `shell/lib/revealui-mcp-env.sh` |

Never put the token in git or `config.toml`.

## Env overrides

| Variable | Default |
|----------|---------|
| `REVFLEET_ROOT` | `$HOME/revfleet` |
| `REVEALUI_MCP_URL` | `https://api.revealui.com/api/mcp` |
| `REVEALUI_MCP_TOKEN_VAULT_PATH` | `revealui/dev/mcp/cli-token` |
| `REVEALUI_MCP_ENV_SKIP=1` | skip vault load (debug) |
| `REVEALUI_MCP_ENV_STRICT=0` | launch even if token missing |

Local API:

```bash
REVEALUI_MCP_URL=http://localhost:3004/api/mcp rfg revealui
```

## Install

Shipped with RevKit. Bootstrap deploys `shell/bin/*.sh` to `/usr/local/bin`
(or `~/.local/bin` on macOS) and sources `shellrc.d/*.sh` from `.bashrc`:

```bash
# from revkit checkout
bash bootstrap.sh
source ~/.bashrc
```

Immediate without full bootstrap:

```bash
ln -sfn ~/revfleet/revkit/shell/bin/rfg.sh ~/.local/bin/rfg.sh
# ensure shellrc.d is sourced (revkit rc hook) or:
source ~/revfleet/revkit/shell/shellrc.d/55-rfg.sh
```

## RevCon / RevSkills

| Product | Role |
|---------|------|
| **RevKit** | Launcher + shell aliases (this doc) |
| **RevCon** | Editor/agent *content* generators — not the shell entrypoint |
| **RevSkills** | Skills (`revealui-mcp`, doctor) document `rfg`; no second secret path |

## Related

- `~/.grok/REVEALUI-MCP-ATTACH.md` — Level 1 attach design
- GAP-371 OpenCode — same data-plane (device token + `/api/mcp`)
