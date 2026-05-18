---
type: master-spec
repo: revkit
last-updated: 2026-05-10
owner: RevealUI Studio
staleness-status: FRESH
---

# RevKit — Master Spec

**Last Updated:** 2026-05-10
**Status:** Pre-1.0 — surface stable for Joshua's primary use; external-contributor flow is Phase 2
**Repo:** [RevealUIStudio/revkit](https://github.com/RevealUIStudio/revkit) (product name: RevealUI DevKit)

> Surface area, architecture, render contract. Companion to [`MASTER_PLAN.md`](./MASTER_PLAN.md) (status + roadmap).

---

## Mission

Portable WSL development-environment toolkit. Take a Windows host with WSL2 and turn it into a RevealUI Studio-grade workstation, declaratively, from a TOML profile.

---

## Repository structure

```
revkit/
├── README.md
├── bootstrap.ps1                    # Windows-host entrypoint (PowerShell)
├── bootstrap-wsl.sh                 # WSL-host entrypoint (bash)
├── profiles/                        # TOML profile presets
│   ├── solo-dev.toml                # T0, 8GB RAM, 4 cores
│   ├── full-stack.toml              # T1, 12GB RAM, 8 cores
│   ├── ai-studio.toml               # T1+, 16GB RAM, 8 cores, Ollama
│   ├── team.toml                    # T1, 16GB RAM, 8 cores, no Ollama
│   └── config.example.toml          # template for custom profiles
├── scripts/
│   ├── render.sh                    # TOML profile → ~/.revealui/ tree
│   └── weekly-wsl-backup.ps1        # scheduled task — exports Ubuntu distro
├── wsl/
│   ├── bashrc.d/                    # shell config fragments sourced by .bashrc
│   │   └── 00-base.sh               # tier detection, PATH, env vars
│   ├── bin/                         # helper scripts → /usr/local/bin
│   ├── config/                      # wsl.conf, .wslconfig, gitconfig, ssh-config, systemd drop-ins
│   ├── docker/                      # Docker-related config (T1 services)
│   ├── setup-wsl-boot.sh            # idempotent boot optimization (--revert supported)
│   ├── compact-vhdx.ps1             # VHDx compaction helper
│   └── Register-VHDxCompactTask.ps1
├── powershell/
│   └── Modules/
│       └── RevealUI.RevStation/     # PowerShell module (Mount-WSLDev, Sync-RevealUIToWindows, etc.)
├── editor-configs/                  # portable editor settings (Zed)
├── templates/
│   └── hooks/                       # workboard.template.md (file-based coord template)
├── docs/                            # this directory
├── tests/
└── backups/
```

---

## Profile schema

Profiles are TOML. Render-time keys:

```toml
[identity]
name = "Joshua Vaughn"
email = "joshua.v.dev@gmail.com"
git_signing_key = "..."

[wsl]
distro = "Ubuntu"
ram_gb = 12
cores = 8
swap_gb = 4

[tier]
sandbox_drive = true       # T1 if true, T0 if false
docker = true
ollama = false             # T1+ if true

[node]
version = "24"
package_manager = "pnpm"

[shell]
aliases = [
  "ll = ls -la",
  "..= cd ..",
]

[editors]
zed = true
vscode = false
cursor = false

[secrets]
age_identity_path = "~/.age-identity/keys.txt"  # RevVault expects this
```

### Render contract

`scripts/render.sh --config <profile> --output <tree>` produces:

| Output path | Source | Purpose |
|---|---|---|
| `<tree>/wsl/bashrc.d/*.sh` | `wsl/bashrc.d/` | Shell config fragments (tier-aware) |
| `<tree>/wsl/bin/*` | `wsl/bin/` | Helper scripts to symlink into `/usr/local/bin` |
| `<tree>/wsl/config/wsl.conf` | `wsl/config/wsl.conf` | WSL distro config (`appendWindowsPath=false`, etc.) |
| `<tree>/wsl/config/.wslconfig` | `wsl/config/wslconfig` | Windows-host WSL global config (memory, processors) |
| `<tree>/wsl/config/.gitconfig` | template + `[identity]` | Git identity + signing |
| `<tree>/wsl/config/.ssh/config` | template | SSH host aliases (`github.com-revealui` for org-owner key) |
| `<tree>/editor-configs/*` | `editor-configs/` | Zed/VS Code/Cursor settings |
| `<tree>/scripts/*` | `scripts/*` | Backup guards, weekly-backup, etc. |

`render.sh` flags:

| Flag | Behavior |
|---|---|
| `--dry-run` | Preview without writing |
| `--diff <existing-tree>` | Show diff against an existing render |
| `--verbose` | Print every file written |

---

## Tier model

| Tier | Trigger | Capabilities |
|---|---|---|
| **T0** | Sandbox drive not mounted | Shell env, git+SSH, Node (fnm), age secrets, Chrome bridge, `sandbox` CLI partial (help/validate work; `up` blocked) |
| **T1** | Sandbox drive mounted at `/mnt/sandbox` | All T0 + Docker services, Postgres (5433), Redis (6380), Ollama (11434, T1+ only via `sandbox up --ai`), build/package caches, `sandbox validate` full |

**Tier transitions** are detected automatically on shell login by `00-base.sh`. The `sandbox validate` command verifies tier consistency (no env-var drift between expected + actual).

Per the internal `project_forge_drive_role` memory entry, the sandbox drive's role changed 2026-04-24 from "primary dev infra" to "product-demo + red-team security-research lab." The T1 capabilities above remain documented for completeness but are NOT the recommended deployment for daily dev infra — `pnpm store`, Docker data-root, Ollama models, build caches, and active ext4 working trees should stay on the primary WSL ext4 vhdx, not the sandbox drive (NTFS/9p hostile + USB unplugability).

### Env vars

| Variable | T0 | T1 | Purpose |
|---|---|---|---|
| `DEVKIT_TIER` | `T0` | `T1` | Shell-detectable tier signal |
| `REVEALUI_ROOT` | set (C:) | set (C:) | Studio root dir on Windows |
| `REVEALUI_SANDBOX` | `/mnt/sandbox` | `/mnt/sandbox` | Sandbox-drive mount point (post-revkit#13) |
| `REVEALUI_SANDBOX_MOUNTED` | unset | `1` | Boolean signal |
| `SANDBOX_DATABASE_URL` | set (string) | set (string) | Postgres conn string at port 5433 |
| `SANDBOX_REDIS_URL` | set (string) | set (string) | Redis conn string at port 6380 |

**Drift note:** Joshua's deployed WSL still uses the legacy `forge` names (`/mnt/forge`, `REVEALUI_FORGE`, `mount-forge-drive.sh`). Source repo post-revkit#13 uses `sandbox` names. Rebootstrap pending (no functional impact).

---

## PowerShell surface (`RevealUI.RevStation` module)

| Cmdlet | Purpose |
|---|---|
| `Mount-WSLDev` | Mount the sandbox/forge drive into WSL via `wsl --mount` |
| `Sync-RevealUIToWindows` | One-shot mirror of the WSL RevealUI tree to a Windows path (manual / `wslsync` alias) |
| `Compact-VHDx` | Compact the WSL ext4.vhdx file to reclaim disk |
| `Register-VHDxCompactTask` | Install scheduled task to compact VHDx weekly |

Module discovery: profile chain in `C:\Program Files\PowerShell\7\profile.ps1` → sources `~\.config\shell\profile.ps1` → loads RevealUI.RevStation when E: connected.

---

## Boot optimization

`wsl/setup-wsl-boot.sh` (idempotent, supports `--revert`):

- Deploys `wsl.conf`, `.wslconfig`, login barrier drop-in
- Masks 23 hardware/desktop services unnecessary in WSL
- Disables Docker + snap auto-start (sockets preserved for on-demand activation)
- Default systemd target: `multi-user.target` (skips graphical/multi-user transitions)
- Login barrier: same-name override in `/etc/systemd/system/` required (separate `99-` file does NOT work in systemd 255)
- WSL 2.7.0 pre-release recommended (`wsl --update --pre-release`)

---

## Backup model

**Weekly WSL `.tar` snapshot** — `weekly-wsl-backup.ps1` runs Sunday 03:00 via scheduled task `RevealUI-WSL-Weekly-Backup`; exports Ubuntu distro to `E:\backups\wsl-snapshots\current\Ubuntu-<date>.tar`; keeps 2 most recent. Recovery: `wsl --import`.

The previous Windows-side mirror infrastructure (read-only `E:\projects\*` clones synced by the `RevealUI-Repo-Sync` 30-min scheduled task; backup-guard pre-commit/pre-push hooks; `install-backup-guards.ps1` installer) was retired 2026-05-08 (the sync task had been silently broken since 2026-05-01 due to the `RevealUI.DevEnv` → `RevealUI.RevStation` module rename). GitHub remotes + the weekly WSL snapshot above are now the redundancy layer.

---

## File-based workboard template

`templates/hooks/workboard.template.md` ships an alternative coord mode for projects that don't run the RevDev daemon. Two legitimate use cases:

1. **Lightweight bootstrap** — greenfield/one-off project; Node + markdown only
2. **Offline / minimal-dep setup** — no Rust, no socket, no daemon

For RevFleet products: skip the workboard hooks and wire the RevDev daemon instead (see [`hooks-architecture.md`](https://github.com/RevealUIStudio/revealui/blob/main/.claude/rules/hooks-architecture.md)).

---

## Versioning

Pre-1.0. Profile schema versioning lives inside the profile itself (`schema_version = 1` in TOML); breaking schema changes bump the schema-version field and add a migration script under `scripts/migrate-profile-vN-to-vN+1.sh`.

---

## Compose / coexistence

| Other product | Relationship |
|---|---|
| **RevealUI** | Independent — RevealUI runs anywhere with Node 24 + pnpm + Postgres; RevKit is one provisioning option |
| **RevVault** | RevKit sets up `~/.age-identity/keys.txt` mount path RevVault expects |
| **RevDev** | Independent — RevDev's harness daemon runs on whatever workstation RevKit (or any other tool) provisioned |
| **RevCon** | Pairs cleanly — RevKit installs portable Zed config; RevCon overlays project-specific configs via symlinks |
| **RevForge** | Independent — RevForge runs on a workstation; RevKit can provision that workstation |
| **RevealCoin** | Independent |
| **RevSkills** | Independent — skills are markdown, work in any RevKit-provisioned env |

---

## See also

- [`docs/MASTER_PLAN.md`](./MASTER_PLAN.md) — current status, phases, owner actions
- [`docs/tier-capabilities.md`](./tier-capabilities.md) — full T0/T1 capability matrix
- [`docs/agent-coordination.md`](./agent-coordination.md) — workboard template + alternative coord mode
- [`docs/WSL-CheatSheet.txt`](./WSL-CheatSheet.txt), [`docs/WSL-QuickReference.md`](./WSL-QuickReference.md)
- [`README.md`](../README.md) — quick start
- Fleet master index (`MASTER_INDEX.md` in the RevealUI Studio internal coordination hub) — fleet-level navigation
