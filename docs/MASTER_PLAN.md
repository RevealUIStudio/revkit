# RevKit — Master Plan

**Last Updated:** 2026-05-10
**Status:** Active — TOML-profile bootstrap for WSL workstations; sandbox-drive rename shipped (revkit#13)
**Owner:** RevealUI Studio (`founder@revealui.com`)
**Repo:** [RevealUIStudio/revkit](https://github.com/RevealUIStudio/revkit) (product name: RevealUI DevKit)
**Fleet master index:** RevealUI Studio internal coordination hub (`MASTER_INDEX.md`, private).

> Fleet-level cross-cutting plans live in the internal coordination hub's `MASTER_PLAN.md`. This file is RevKit-scoped only.

---

## Current Reality (2026-05-10)

### What exists

- **Bootstrap scripts** for WSL2 (Ubuntu) → installs Nix + direnv, fnm, Node 24, pnpm, base shell aliases
- **TOML profile presets** at `profiles/`: `solo-dev` (T0, 8GB), `full-stack` (T1, 12GB), `ai-studio` (T1+, 16GB + Ollama), `team` (T1, 16GB)
- **Render pipeline** at `scripts/render.sh` — TOML profile → personal `~/.revealui/` tree
- **Tier detection** in `wsl/bashrc.d/00-base.sh` — `DEVKIT_TIER=T0` (no sandbox drive) or `T1` (mounted)
- **Boot optimization** — `wsl/setup-wsl-boot.sh` masks 23 hardware/desktop services, disables Docker/snap auto-start (sockets preserved); supports `--revert`
- **Editor configs** — portable Zed settings (extends RevCon for the rest)
- **PowerShell module** `RevealUI.RevStation` — `Sync-AllRepos`, `Mount-WSLDev`, `Compact-VHDx` helpers
- **Sandbox-drive support** — optional ext4 USB at `/mnt/sandbox` for product-demo + red-team work (NOT primary dev infra per the internal `project_forge_drive_role` memory entry)
- **Backup guards** — pre-commit + pre-push hooks; weekly-WSL-backup PowerShell script (scheduled task)
- **Workboard template** — file-based coord (alternative to RevDev daemon RPC) for greenfield/offline projects

### What works (verified by code + revkit#13 ship)

| Capability | Status | Confidence |
|---|---|---|
| `bootstrap-wsl.sh` from a fresh WSL install → working RevealUI environment | Built | High — pattern proven, used by Joshua's standing setup |
| TOML profile → `~/.revealui/` render | Built | High — `scripts/render.sh` with `--dry-run` + `--diff` |
| Tier detection (`T0`/`T1`) | Built | High — auto-detected on shell login |
| `setup-wsl-boot.sh` (boot optimization) | Built | High — `--revert` supported; idempotent |
| PowerShell module install | Built | High |
| Sandbox-drive mount script | Built | Medium — source uses `/mnt/sandbox` post-revkit#13; deployed checkout still uses `/mnt/forge` (rebootstrap pending) |
| Pre-commit + pre-push backup guards | Built | High |
| Weekly WSL `.tar` snapshot rotation | Built | High |

### Known drift between source + deployment (per memory)

| Layer | Source (revkit `main`) | Deployed in Joshua's WSL |
|---|---|---|
| Drive mount label + path | `Sandbox` / `/mnt/sandbox` (post-revkit#13 MERGED 2026-05-02) | Still `Forge` / `/mnt/forge` (rebootstrap pending) |
| Mount script | `mount-sandbox-drive.sh` | `mount-forge-drive.sh` |
| Env var | `REVEALUI_SANDBOX` | `REVEALUI_FORGE` |

**Action:** rebootstrap deployed environment when convenient. Memory `project_forge_drive_role` documents this split.

---

## Composition with the rest of RevFleet

RevKit is the workstation. Other RevFleet products run on top of what RevKit provisions:

- **New contributor onboarding**: plug a USB into a Windows host → boot WSL → run `bootstrap-wsl.sh` → working studio environment in minutes
- **Reproducibility**: every dev workstation in RevFleet builds from the same RevKit profile (Nix version, Node version, pnpm version, shell aliases, PATH order)
- **Pairs with RevVault**: RevKit sets up the age-identity mount path RevVault expects (`~/.age-identity/keys.txt`)
- **Pairs with RevCon**: RevKit installs portable Zed config; RevCon manages the project-specific symlink overlays
- **Independent of RevealUI**: RevKit is a workstation toolkit, not a runtime dependency. RevealUI runs in environments RevKit didn't provision (CI, Vercel, etc.)

---

## Active Work

### `chore/devkit-bashrc-drift-reconciliation` (current branch)

Peer agent reconciling drift between `wsl/bashrc.d/` source files and what's actually deployed in `~/.revealui/wsl/bashrc.d/`. No release blockers.

### Recently shipped

- **revkit#13** (MERGED 2026-05-02) — drive label + path rename `forge` → `sandbox`. Source-side update; deployment rebootstrap pending.
- WSL boot optimization (`setup-wsl-boot.sh`) finalized; default `multi-user.target`; login barrier drop-in.
- Backup guards (`backup-guard-pre-commit.sh`, `backup-guard-pre-push.sh`) and `Register-VHDxCompactTask.ps1`.
- `weekly-wsl-backup.ps1` scheduled task (Sunday 03:00) — exports Ubuntu distro to `E:\backups\wsl-snapshots\current\`.

---

## Roadmap

Pre-1.0 per the fleet versioning convention (RevealUI Studio internal). Promotion gated on real external consumers (other contributors using RevKit to bootstrap their own machines).

### Phase 0 — Single-developer bootstrap (DONE)

Profile-driven bootstrap for Joshua's primary + secondary machines. Deployed environment runs from `~/.revealui/` rendered from `solo-dev.toml`/`full-stack.toml`.

### Phase 1 — Drift cleanup + sandbox migration (IN FLIGHT)

- Reconcile `bashrc.d/` source vs deployed (current branch)
- Re-bootstrap deployed environment to pick up revkit#13 sandbox-drive rename
- Document deploy-vs-source split until rebootstrap completes

### Phase 2 — External-contributor onboarding (NOT STARTED)

- Polish `bootstrap-wsl.sh` for non-Joshua-machine first-run
- Document profile customization for orgs other than RevealUI Studio
- CI smoke test that simulates a fresh WSL bootstrap end-to-end

### Phase 3 — Mac / Linux native bootstrap (NOT STARTED)

Currently WSL-only. Mac/Linux native bootstraps need:
- macOS-equivalent of `wsl/setup-wsl-boot.sh` (likely a no-op + Nix install + dotfiles)
- Linux-native equivalent (most of WSL config translates directly)

---

## Owner Action Queue

| Item | Unblocks |
|---|---|
| Re-bootstrap Joshua's deployed WSL to pick up `/mnt/sandbox` paths | Closes the source-vs-deploy drift |
| Decide whether RevKit should be public on GitHub or stay studio-internal | Phase 2 (external onboarding) |

---

## See also

- [`docs/MASTER_SPEC.md`](./MASTER_SPEC.md) — surface area + render contract
- [`docs/tier-capabilities.md`](./tier-capabilities.md) — T0/T1 capability matrix
- [`docs/agent-coordination.md`](./agent-coordination.md) — file-based workboard template (alternative to RevDev daemon)
- [`docs/WSL-CheatSheet.txt`](./WSL-CheatSheet.txt) + [`docs/WSL-QuickReference.md`](./WSL-QuickReference.md) — WSL ops reference
- [`README.md`](../README.md) — quick start
- Fleet master index (`MASTER_INDEX.md` in the RevealUI Studio internal coordination hub) — fleet-level navigation
