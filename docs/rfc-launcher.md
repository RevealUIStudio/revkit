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
rfc                  # use $PWD if it is under ~/revfleet, else list repos
rfc revealui         # cd ~/revfleet/revealui && exec claude
rfc revealui --continue   # trailing args pass through to claude verbatim
```

Tab-completion over `~/revfleet/*` is provided in managed interactive shells.
Override the fleet root with `REVFLEET_ROOT`.

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
automatically — both by `bootstrap-wsl.sh` (no extra step):

```bash
bash /mnt/c/Users/$USER/.revealui/bootstrap-wsl.sh
# then, for the short `rfc` command + completion in the current shell:
source ~/.bashrc
```
