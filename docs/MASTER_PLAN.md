---
type: master-plan
repo: revkit
last-updated: 2026-06-23
owner: RevealUI Studio
staleness-status: FRESH
---

# RevKit — Master Plan

**Last Updated:** 2026-06-23
**Status:** Active — cross-platform (macOS + Linux + WSL2) bootstrap + WSL-native secure sessions shipped; onboarding validation + drift cleanup next
**Owner:** RevealUI Studio (`founder@revealui.com`)
**Repo:** [RevealUIStudio/revkit](https://github.com/RevealUIStudio/revkit) (product name: RevealUI DevKit)
**Fleet master index:** RevealUI Studio internal coordination hub (`MASTER_INDEX.md`, private).

> Fleet-level cross-cutting plans live in the internal coordination hub's `MASTER_PLAN.md`. This file is RevKit-scoped only.
>
> **Phase labels:** This plan is the canonical phase source. Earlier session handoffs used informal letter labels (e.g. "B3", "C + D"); the canonical mapping is spelled out under [Roadmap](#roadmap). The pre-2026-06 numbered scheme (Phase 0/1/2/3) is reconciled into the lettered scheme there.

---

## Current Reality (2026-06-23)

### What exists

- **Bootstrap scripts** — `bootstrap.sh` (the cross-platform forward path: dispatches on `REVKIT_OS` from `lib/platform.sh`, supports macOS + native Linux + WSL2) and the legacy `bootstrap-wsl.sh` (kept for backwards compatibility). Installs Nix + direnv, fnm, Node 24, pnpm, base shell aliases. WSL-only steps (sudoers, boot optimization, sandbox init) gated behind `revkit_is_wsl`.
- **Platform abstraction** — `lib/platform.sh` exposes `REVKIT_OS` (`macos` / `linux` / `wsl`) + `revkit_is_wsl`; WSL-only helpers (`mount-sandbox-drive.sh`, `sandbox-services.sh`, `sandbox-validate.sh`, `wsl-status.sh`) skipped on macOS/Linux.
- **Shell fragment system** — `shell/shellrc.d/` numbered fragments appended to `.bashrc` + `.zshrc`; includes `45-with-secrets.sh` (the `with-secrets <ns...> -- <cmd>` point-of-use secret wrapper) and `15-docker.sh` (docker DB creds constructed at point-of-use inside `forge()`, not broadcast into the global shell).
- **WSL-native secure sessions** — `rf` / `rfclaude` / `rfc` launchers run natively on macOS + Linux + WSL (reconciled in #66); `claude-safe` crash-recovery wrapper + zero-prompt profile.
- **TOML profile presets** at `profiles/`: `solo-dev` (T0, 8GB), `full-stack` (T1, 12GB), `ai-studio` (T1+, 16GB + Ollama), `team` (T1, 16GB).
- **Render pipeline** at `scripts/render.sh` — TOML profile → personal `~/.revealui/` tree (`--dry-run` + `--diff`).
- **Tier detection** in `wsl/bashrc.d/00-base.sh` — `DEVKIT_TIER=T0` (no sandbox drive) or `T1` (mounted).
- **Boot optimization** — `wsl/setup-wsl-boot.sh` masks 23 hardware/desktop services, disables Docker/snap auto-start (sockets preserved); supports `--revert`.
- **Editor configs** — portable Zed settings (extends RevCon for the rest).
- **PowerShell module** `RevealUI.RevStation` — `Mount-WSLDev`, `Compact-VHDx`, `Sync-RevealUIToWindows` helpers.
- **Sandbox-drive support** — optional ext4 USB at `/mnt/sandbox` for product-demo + red-team work (NOT primary dev infra per `project_sandbox_drive_role`).
- **Weekly WSL backup** — `weekly-wsl-backup.ps1` scheduled via `RevealUI-WSL-Weekly-Backup` (Sunday 03:00) → `E:\backups\wsl-snapshots\current\`.
- **Security scanning** — CodeQL (security-and-quality) on the repo (#69); plus Gitleaks (full history), Private Leak Scan, GAP-116 anti-regression, PowerShell Pester + parse, ShellCheck + `bash -n` in CI.
- **Workboard template** — file-based coord (alternative to RevDev daemon RPC) for greenfield/offline projects.

### What works (verified by code + ship)

| Capability | Status | Confidence |
|---|---|---|
| `bootstrap.sh` cross-platform (macOS/Linux/WSL2) | Built | High — #68; `--dry-run` verified per-OS in PR checklist (real-machine smoke = Phase C) |
| `bootstrap-wsl.sh` from fresh WSL → working RevealUI environment | Built | High — proven, Joshua's standing setup |
| Native `rf`/`rfclaude`/`rfc` on macOS + Linux | Built | High — #66 |
| `with-secrets <ns> -- <cmd>` point-of-use secret scoping | Built | High — #71; `tests/test-secrets.sh` green; subshell+`exec`, no leak-back |
| TOML profile → `~/.revealui/` render | Built | High — `scripts/render.sh` (`--dry-run` + `--diff`) |
| Tier detection (`T0`/`T1`) | Built | High — auto-detected on shell login |
| `setup-wsl-boot.sh` (boot optimization) | Built | High — `--revert` supported; idempotent |
| CodeQL security scanning | Built | High — #69 |
| PowerShell module install | Built | High |
| Sandbox-drive mount script | Built | Medium — source uses `/mnt/sandbox` post-#13; deployed checkout may still use `/mnt/forge` (verify; rebootstrap = Phase D) |
| Weekly WSL `.tar` snapshot rotation | Built | High |

### Known drift between source + deployment

| Layer | Source (revkit `test`) | Deployed in Joshua's WSL (confirmed 2026-06-23) |
|---|---|---|
| Drive mount label + path | `Sandbox` / `/mnt/sandbox` (post-#13, MERGED 2026-05-02) | **Still `Forge` / `/mnt/forge`** — `/mnt/forge` is what's mounted |
| Env var | `REVEALUI_SANDBOX` | **`REVEALUI_FORGE`** — refs in `~/.revealui/wsl/bashrc.d/00-base.sh` + `wsl/docker/{compose.yml,.env.example}` |

**Action:** rebootstrap deployed environment to pick up `/mnt/sandbox` (Phase D). Memory `project_sandbox_drive_role` documents this split. Note: #71 installed updated `shellrc.d` copies into `~/.revealui/wsl/bashrc.d/`, so parts of the deployed tree are in sync; the **drive-path drift is confirmed still open** as of 2026-06-23.

---

## Composition with the rest of RevFleet

RevKit is the workstation. Other RevFleet products run on top of what RevKit provisions:

- **New contributor onboarding**: plug a USB into a host → bootstrap → working studio environment in minutes (cross-platform as of Phase B; CI-validated in Phase C)
- **Reproducibility**: every dev workstation in RevFleet builds from the same RevKit profile (Nix version, Node version, pnpm version, shell aliases, PATH order)
- **Pairs with RevVault**: RevKit sets up the age-identity mount path RevVault expects (`~/.age-identity/keys.txt`); the `with-secrets` wrapper (Phase B5) scopes RevVault namespaces to the process that needs them
- **Pairs with RevCon**: RevKit installs portable Zed config; RevCon manages the project-specific symlink overlays
- **Independent of RevealUI**: RevKit is a workstation toolkit, not a runtime dependency. RevealUI runs in environments RevKit didn't provision (CI, Vercel, etc.)

---

## Active Work

- **#72 — `ci(bootstrap): cover bootstrap.sh in M-11 check; bootstrap-wsl.sh → shim`** (OPEN, base `test`) — adds `bootstrap.sh` to the M-11 CI check and reduces `bootstrap-wsl.sh` to a shim delegating to `bootstrap.sh`. Overlaps early Phase C (CI coverage of the cross-platform bootstrap).

**Next lane: Phase C + D** (see Roadmap) — branch off `revkit` `origin/test`.

### Recently shipped (2026-06)

- **#71** (MERGED 2026-06-23) — `with-secrets` wrapper + docker-creds point-of-use (GAP-251 part B). `.envrc` 9-namespace broadcast removed; secrets scoped per-process via subshell+`exec`.
- **#69** (MERGED) — CodeQL (security-and-quality) code scanning.
- **#68** (MERGED) — cross-platform `bootstrap.sh` (macOS + Linux + WSL2) via `REVKIT_OS` / `lib/platform.sh`; WSL-only steps gated.
- **#67** (MERGED) — gate WSL-only chrome-bridge fragment off non-WSL.
- **#66** (MERGED) — native `rfc` on macOS + Linux; reconcile `rf`/`rfclaude`.
- **#13** (MERGED 2026-05-02) — drive label + path rename `forge` → `sandbox` (source-side; deployment rebootstrap pending).

---

## Roadmap

Pre-1.0 per the fleet versioning convention. Promotion gated on real external consumers (other contributors using RevKit to bootstrap their own machines).

**Canonical phase scheme** (reconciles the pre-2026-06 numbered phases into the lettered labels used in session handoffs):

### Phase A — Single-developer WSL bootstrap (DONE)
*(was Phase 0)* Profile-driven bootstrap for Joshua's primary + secondary machines; deployed `~/.revealui/` rendered from `solo-dev`/`full-stack` TOML. Tier detection, boot optimization, weekly backup.

### Phase B — Cross-platform + WSL-native secure sessions (DONE — shipped 2026-06)
*(was Phase 3 "Mac/Linux native bootstrap" + the WSL-native-secure-sessions RFC thread; the phase the handoffs call "B", with "B3" = #68)*

- **B1** — native `rfc`/`rf`/`rfclaude` on macOS + Linux (#66)
- **B2** — gate WSL-only fragments off non-WSL (chrome-bridge) (#67)
- **B3** — cross-platform `bootstrap.sh` via `REVKIT_OS` / `lib/platform.sh` (#68)
- **B4** — CodeQL security scanning (#69)
- **B5** — point-of-use secret scoping: `with-secrets` + docker-creds (#71, GAP-251 part B)

### Phase C — Cross-platform onboarding, validated (NEXT)
*(was Phase 2 "External-contributor onboarding" + real-machine validation of Phase B)*

- Fresh-bootstrap CI smoke on a **macOS + Linux + WSL matrix** — proves #66/#68 work on real OSes, not just `--dry-run`
- Non-owner first-run polish for `bootstrap.sh` (machines that aren't Joshua's)
- Profile-customization docs for orgs other than RevealUI Studio
- **Exit:** a contributor on a fresh macOS/Linux/WSL machine runs `bootstrap.sh` → working environment, validated in CI

### Phase D — Drift cleanup + public-readiness (NEXT)
*(was Phase 1 "Drift cleanup + sandbox migration" + macOS boot no-op + the public/internal decision)*

- Finish the `bashrc.d/` source-vs-deployed reconciliation + rebootstrap deployed env to `/mnt/sandbox` paths (closes the source-vs-deploy drift)
- macOS boot-equivalent of `setup-wsl-boot.sh` (likely a no-op + Nix install + dotfiles)
- Resolve **public-vs-internal GitHub** decision (owner) — gates Phase C completion
- **Exit:** zero source-vs-deploy drift; macOS/Linux paths first-class; public/internal posture decided

> **Phase order note:** C and D are independent and can run in either order or in parallel (separate PRs). C is forward-looking (validate the cross-platform work); D is cleanup (close the deploy drift + decide posture). The public/internal decision in D is the only owner-gated item — flag it rather than block on it.

---

## Owner Action Queue

| Item | Unblocks |
|---|---|
| Re-bootstrap Joshua's deployed WSL to pick up `/mnt/sandbox` paths | Closes source-vs-deploy drift (Phase D) |
| Decide whether RevKit is public on GitHub or stays studio-internal | Phase C (external onboarding) completion |

---

## See also

- [`docs/MASTER_SPEC.md`](./MASTER_SPEC.md) — surface area + render contract
- [`docs/tier-capabilities.md`](./tier-capabilities.md) — T0/T1 capability matrix
- [`docs/agent-coordination.md`](./agent-coordination.md) — file-based workboard template (alternative to RevDev daemon)
- [`docs/WSL-CheatSheet.txt`](./WSL-CheatSheet.txt) + [`docs/WSL-QuickReference.md`](./WSL-QuickReference.md) — WSL ops reference
- [`README.md`](../README.md) — quick start
- Fleet master index (`MASTER_INDEX.md` in the RevealUI Studio internal coordination hub) — fleet-level navigation
