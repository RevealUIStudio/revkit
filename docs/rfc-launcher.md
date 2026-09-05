# `rfc` — RevFleet Claude launcher (secure, zero-prompt)

`rfc` starts a Claude Code session whose **process runs inside WSL**, rooted in
a RevFleet repo. That single property — claude running in WSL rather than on
the Windows host — is what makes a secure, prompt-free session possible.

## Why this exists

When `claude` runs on the **Windows host** and operates on the WSL filesystem,
every shell command it issues is wrapped:

```
wsl.exe -d Ubuntu -- bash -lc '<arbitrary command>'
```

That wrapper breaks permissions two ways:

1. **Un-allowlistable.** The real command is an opaque string inside the
   quotes, so no narrow prefix rule can match it. The only rule that covers it
   is `Bash(wsl.exe *)` — which approves *any* command, i.e. it is
   `bypassPermissions` by the back door.
2. **Hook bypass.** The PreToolUse deny-list hook never sees the inner command,
   so `.env`/lockfile/destructive-op guards do not fire on wrapped calls.

When `claude` runs **inside WSL**, its commands are native (`git status`, not
the wrapper). Native commands allowlist by real prefix, and the
`~/.claude/settings.local.json` allow/deny posture (`defaultMode: acceptEdits`
+ the destructive-op deny list) plus the PreToolUse hooks all apply. That is
the secure zero-prompt configuration.

## Usage

```bash
rfc                  # use $PWD if inside the fleet (root or a repo)
rfc revealui         # cd product checkout + exec claude
# Fleet root is a valid session — rfc / rfc . there does not exit 2.

rfc revealui --continue   # trailing args pass through to claude verbatim

rfc smoke             # auth + MCP health (no secret print)
rfc mint              # OTP → revvault
rfc env               # non-secret URL + vault path only (never the token)

rfc revealui          # loads RevealUI MCP when a token is vaulted (warn, do not
                      # block, unless RFC_MCP_STRICT=1)

# Worktrees (same isolation as rfg: origin/test, hash ports, PID/TTL claims)
rfc open revealui ves-fo-managed --claim marketing/ves-fo-managed
rfc bootstrap ~/revfleet/.wt/ves-fo-managed
rfc claim acquire revealui marketing/ves-fo-managed
rfc claim list
rfc claim release revealui marketing/ves-fo-managed
rfc claim sweep

The PATH name `revealui` (tmux workspace launcher) is retired — GAP-351.
Use `rfc <repo>` or `rfg <repo>`, not a multiplexer.
```

Tab-completion over `~/revfleet/*` plus `mint|smoke|env|bootstrap|claim|open|help`
is provided in managed interactive shells. Override the fleet root with
`REVFLEET_ROOT`. Worktree ports and claims share `shell/lib/worktree-env.sh`
with `rfg` (same `.env.worktree` and `~/.local/share/revealui/claims/`).

`rfc env` never prints `REVEALUI_MCP_TOKEN`. Claude can launch without a
device token (unlike `rfg`, which is strict by default). Set `RFC_MCP_STRICT=1`
to fail closed.

## Per-surface wiring

| Surface | Secure WSL-native? | How |
|---|---|---|
| WSL terminal | Yes | `rfc <repo>` |
| Claude Code terminal | Yes (launch inside WSL) | `rfc <repo>` |
| Zed integrated terminal | Yes | open the project via the Ubuntu `wsl_connections` entry, then `rfc` (or the Zed task below) |
| Zed Claude extension (`claude-acp`) | Yes — **only** when the project is opened through the WSL connection | the ACP agent then runs remotely in WSL; nothing else to configure |
| Claude Desktop (Windows) | **No** | its local agent ("Cowork") runs on the Windows host with no setting to target WSL. Use Desktop for chat + MCP, not fleet code execution. |

### Zed task

Copy `editor-configs/zed/tasks.json` to `~/.config/zed/tasks.json` (WSL-remote
Zed, global) or a project `.zed/tasks.json`. Run it from the command palette
(`task: spawn`) or bind a key. The task launches `rfc.sh` in the project
directory, so opening a fleet repo project makes it pick that repo
automatically.

### Zed connection (covers the extension + terminal)

In Zed `settings.json`, an Ubuntu `wsl_connections` entry with a project root
of your WSL home (e.g. `/home/<wsl-user>`) already covers every `~/revfleet/*`
repo. Open fleet repos through that connection (not as a local Windows folder)
and both the integrated terminal and the `claude-acp` agent run native in WSL.

## Install

`rfc.sh` is deployed to `/usr/local/bin/rfc.sh` and `50-rfc.sh` is sourced
automatically — both by `bootstrap.sh` (no extra step):

```bash
bash /mnt/c/Users/$USER/.revealui/bootstrap.sh
# then, for the short `rfc` command + completion in the current shell:
source ~/.bashrc
```

`bootstrap-wsl.sh` still works (it execs `bootstrap.sh`). Prefer `bootstrap.sh` in new instructions.
