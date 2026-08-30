# RevealUI DevKit

Operator machine kit for RevealUI Studio workstations (macOS + Linux + WSL2, WSL-first).
This is **not** a customer runtime, product SDK, or end-user installer.

`bootstrap.sh` provisions the machine that runs the fleet: helper scripts, sudoers, global git hooks, and Claude/Grok launchers. Do not treat a clone of this repo as something to ship to a customer host.

## Privilege warning

A default `bootstrap.sh` run is a privileged install. Preview first (`--dry-run`). It will:

- install helpers to `/usr/local/bin` on Linux/WSL (uses `sudo`; `~/.local/bin` on macOS)
- write WSL sudoers for passwordless sandbox-drive mounting (`/etc/sudoers.d/wsl-revealui`)
- set `git config --global core.hooksPath` to the fleet pre-push hook
- wire fleet Claude rules when `revcon` is present

Do not run this on a customer machine or any host you do not want those changes on.

## Quick Start

`bootstrap.sh` is the universal entry point. It detects the OS (macOS, Linux, or WSL2) and runs the platform-appropriate steps.

### macOS / native Linux

```bash
git clone https://github.com/RevealUIStudio/revkit.git
bash revkit/bootstrap.sh            # add --dry-run to preview
```

### WSL2 (Windows host)

Clone to your Windows home so WSL can reach it via `/mnt/c/`:

```powershell
# From PowerShell
cd $env:USERPROFILE
git clone https://github.com/RevealUIStudio/revkit.git .revealui
```

Then bootstrap from WSL:

```bash
bash /mnt/c/Users/$USER/.revealui/bootstrap.sh
```

> `bootstrap-wsl.sh` still works as a backward-compatible alias. It is now a thin shim that execs `bootstrap.sh` (which auto-detects WSL).

In more detail, the bootstrap also adds a `~/.bashrc`/`~/.zshrc` hook that sources `shell/shellrc.d/*.sh` from the cloned repo, links git and SSH configs via `include.path` (per-user identity stays machine-local in `~/.config/revkit/`), applies WSL boot optimization (WSL), initializes Sandbox drive directories (if `/mnt/sandbox` is mounted), deploys the M-4 sudoers/filesystem security scanner to `~/.claude/hooks/`, and clones/wires `claude-config` into `~/.claude`.

Launchers: **`rfc <repo>`** starts Claude in a fleet repo (WSL-native); **`rfg <repo>`** starts Grok with RevealUI MCP token loaded from revvault (see [`docs/rfg-launcher.md`](docs/rfg-launcher.md)). The old `revealui` tmux workspace launcher is **retired** (GAP-351 / ADR 2026-06-23); `bootstrap.sh` overwrites `~/.local/bin/revealui` with a shim that prints `rfg` / `rfc`.

> **Upgrading from an older install:** the runtime tree moved from `wsl/` to `shell/` (and `bashrc.d/` to `shellrc.d/`). Just re-run `bootstrap.sh` — the rc hook is self-healing and migrates in place. No manual edit needed.

Open a new shell — you should see a `● RevKit: managed` banner. On WSL, run `wsl --shutdown` from Windows to apply the boot optimization.

### Per-machine configuration

RevKit ships **neutral, identity-free configs** under `shell/config/`. Per-user values are kept machine-local and are **not** committed — on bootstrap they are seeded into `~/.config/revkit/`:

- `~/.config/revkit/identity.gitconfig` — your git name + email (seeded from your existing git identity if present)
- `~/.config/revkit/ssh.local` — your SSH host blocks

Edit those files directly; the tracked `gitconfig` / `ssh-config` Include them. There is no profile/render step — that subsystem was removed in favor of this model.

## Structure

```
revkit/
  bootstrap.sh         # Universal entry point (macOS + Linux + WSL2)
  bootstrap-wsl.sh     # Deprecation shim → execs bootstrap.sh
  bootstrap.ps1        # Windows-host PowerShell prep
  lib/platform.sh      # OS detector (REVKIT_OS + capability predicates)
  shell/               # shellrc.d/, bin/, config/, docker/, setup-wsl-boot.sh
  scripts/             # backup + private-leak-scan scripts
  powershell/          # RevealUI.RevStation PowerShell module
  editor-configs/zed/  # portable Zed settings + rfc task
  git-hooks/           # M-11 fleet-wide pre-push hook
  docs/                # documentation
  tests/               # bash + Pester + platform-fixture suites
```

See [`docs/MASTER_SPEC.md`](docs/MASTER_SPEC.md) for the full surface area + configuration model, and [`docs/MASTER_PLAN.md`](docs/MASTER_PLAN.md) for status + roadmap.

## License

MIT

## RevFleet Claude launcher (`rfc`)

`rfc <repo>` starts a Claude Code session whose process runs **inside WSL**,
rooted in a `~/revfleet/*` repo — the configuration that makes a secure,
prompt-free session possible (commands stay native instead of being wrapped in
`wsl.exe`, so they allowlist by real prefix and the deny-list hooks fire). On
macOS and native Linux `rfc` runs the session locally in the target repo.

Deployed automatically by `bootstrap.sh` (`/usr/local/bin/rfc.sh` +
`shell/shellrc.d/50-rfc.sh`). Per-surface wiring (WSL terminal, Zed terminal, Zed
`claude-acp` extension) and the Claude Desktop limitation are documented in
[`docs/rfc-launcher.md`](docs/rfc-launcher.md).
