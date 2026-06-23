# RevKit — Contributor Onboarding

Get from a fresh machine to a working RevealUI Studio development environment.
RevKit is **cross-platform** (macOS, native Linux, WSL2) and **WSL-first**.

## Prerequisites

- `git` and `bash`.
- macOS, native Linux, or Windows + WSL2 (Ubuntu).
- `node` is optional — if absent, the Claude-scanner step is skipped with a warning (everything else still runs).
- No prior RevealUI setup is assumed.

## 1. Clone

```bash
# macOS / native Linux
git clone https://github.com/RevealUIStudio/revkit.git

# WSL2 (clone into your Windows home so WSL reaches it via /mnt/c/)
#   PowerShell:  cd $env:USERPROFILE; git clone https://github.com/RevealUIStudio/revkit.git .revealui
```

## 2. Preview, then bootstrap

`bootstrap.sh` is the single, universal entry point. It detects your OS via
`lib/platform.sh` (`REVKIT_OS` ∈ `macos`/`linux`/`wsl`) and runs only the steps
that apply. **Always preview first:**

```bash
bash bootstrap.sh --dry-run     # prints every step, changes nothing
bash bootstrap.sh               # apply
```

> `bootstrap-wsl.sh` still works (it is a thin shim that execs `bootstrap.sh`) —
> prefer `bootstrap.sh` in new docs and scripts.

## 3. What bootstrap does

| Step | What | Where it runs |
|---|---|---|
| 1 | Install `shell/bin/*` helpers (WSL-only helpers skipped off WSL) | all |
| 2 | Sudoers for passwordless sandbox mount | WSL only |
| 3 | Self-healing rc-hook into `.bashrc`/`.zshrc` | all |
| 4 | Git + SSH config includes (see below) | all |
| 5 | WSL boot optimization | WSL only |
| 6 | Sandbox directory init (if `/mnt/sandbox` mounted) | WSL only |
| 7 | Deploy the M-4 Claude Code scanner hook | all |
| 8 | Wire RevFleet Claude rules via `revcon/link.sh` (skipped if absent) | all |
| 9 | Fleet-wide M-11 pre-push hook (`core.hooksPath`) | all |

## 4. Configuration model — neutral configs, machine-local identity

RevKit ships **identity-free** configs under `shell/config/` (committed). Your
**personal** values stay machine-local and are **never committed** — bootstrap
seeds them into `~/.config/revkit/`:

| File | What you set |
|---|---|
| `~/.config/revkit/identity.gitconfig` | your git `name` + `email` (seeded from your existing git identity if present) |
| `~/.config/revkit/ssh.local` | your SSH `Host` blocks |

The tracked `shell/config/gitconfig` and `shell/config/ssh-config` `include` /
`Include` those files. To set your identity, edit them directly — there is **no
profile or render step** (the old TOML-profile/`render.sh` model was removed).

## 5. Verify

Open a new shell — you should see:

```
● RevKit: managed (/path/to/revkit)
```

On WSL, run `wsl --shutdown` from Windows once to apply the boot optimization.

To start a secure, WSL-native Claude session in a fleet repo, use `rfc <repo>`
(see [`rfc-launcher.md`](./rfc-launcher.md)).

## 6. Upgrading an older install

The runtime tree moved from `wsl/` to `shell/` (and `bashrc.d/` to
`shellrc.d/`). Just re-run `bootstrap.sh` — the rc-hook is self-healing and
migrates in place.

## More

- [`MASTER_SPEC.md`](./MASTER_SPEC.md) — full surface area + configuration model
- [`MASTER_PLAN.md`](./MASTER_PLAN.md) — status + roadmap
- [`tier-capabilities.md`](./tier-capabilities.md) — T0/T1 (sandbox-drive) capabilities
- [`rfc-launcher.md`](./rfc-launcher.md) — the `rfc` secure Claude launcher
- [`WSL-QuickReference.md`](./WSL-QuickReference.md) + [`WSL-CheatSheet.txt`](./WSL-CheatSheet.txt) — WSL ops
