---
type: master-plan
repo: revkit
last-updated: 2026-06-22
owner: RevealUI Studio
staleness-status: FRESH
---

# RevKit — Master Plan

**Last Updated:** 2026-06-22
**Status:** Active — cross-platform foundation shipped (Phase B, #62–#68); repo-truth reconciliation in flight (Phase C)
**Owner:** RevealUI Studio (`founder@revealui.com`)
**Repo:** [RevealUIStudio/revkit](https://github.com/RevealUIStudio/revkit) (product name: RevealUI DevKit)
**Fleet master index:** RevealUI Studio internal coordination hub (`MASTER_INDEX.md`, private).

> Fleet-level cross-cutting plans live in the internal coordination hub's `MASTER_PLAN.md`. This file is RevKit-scoped only.

---

## Current Reality (2026-06-22)

### What exists

- **Universal bootstrap** — `bootstrap.sh` (macOS + Linux + WSL2), detect-then-dispatch via `lib/platform.sh`; `--dry-run` previews. `bootstrap-wsl.sh` is a deprecation shim that execs it (legacy invocation path); `bootstrap.ps1` is the Windows-host prep entrypoint.
- **OS detection** — `lib/platform.sh` sets `REVKIT_OS` ∈ {wsl,linux,macos} and exports capability predicates (`revkit_is_wsl/macos/linux/posix`, `revkit_has_systemd`, `revkit_has_wsl_interop`); tested via `tests/test-platform-detect.sh` + `tests/platform-fixtures/`.
- **`shell/` runtime tree** — `shell/shellrc.d/*.sh` (shell fragments incl. tier detection in `00-base.sh`, `rfc` in `50-rfc.sh`), `shell/bin/` helpers, `shell/config/` (neutral configs), `shell/docker/`, `shell/setup-wsl-boot.sh`.
- **Neutral configs + per-user includes** — tracked configs under `shell/config/` carry no personal identity; per-machine values live machine-local in `~/.config/revkit/` (`identity.gitconfig`, `ssh.local`) and are wired via git `include.path` + ssh `Include`. (Replaced the removed TOML-profile/render subsystem.)
- **`rfc` launcher** — secure WSL-native (and macOS/Linux) Claude launcher; chrome-bridge shell fragment gated to WSL-only.
- **Boot optimization** — `shell/setup-wsl-boot.sh` masks unnecessary services, disables Docker/snap auto-start (sockets preserved); supports `--revert`.
- **PowerShell module** `RevealUI.RevStation` — `Mount-WSLDev`, `Compact-VHDx`, `Sync-RevealUIToWindows`; VHDx helpers ship at `shell/compact-vhdx.ps1` + `shell/Register-VHDxCompactTask.ps1`.
- **Sandbox-drive support** — optional ext4 USB at `/mnt/sandbox` for product-demo + red-team work (NOT primary dev infra per the internal `project_forge_drive_role` memory entry).
- **Weekly WSL backup** — `scripts/weekly-wsl-backup.ps1` scheduled via `RevealUI-WSL-Weekly-Backup` (Sunday 03:00); `scripts/check-backup-staleness.ps1` guards silent failures.
- **Fleet-wide M-11 pre-push hook** — `git-hooks/pre-push` wired via global `core.hooksPath` (rejects direct/force/unsigned pushes to main + test); M-4 Claude scanner deployed to `~/.claude/hooks/`.
- **CI** — `bash -n` over all `.sh`, ShellCheck, PowerShell parse + Pester, platform-fixture detection, gitleaks, private-leak scan, secrets + pre-push hook tests, GAP-116 no-hardcoded-user, bootstrap M-11 wiring, CodeQL (#69).

### What works (verified by code + CI)

| Capability | Status | Confidence |
|---|---|---|
| `bootstrap.sh` cross-platform install (macOS + Linux + WSL2) | Built | High — used by standing setup; `--dry-run` supported |
| OS detection (`lib/platform.sh`) | Built | High — fixture-tested in CI |
| Neutral configs + per-user `include.path` | Built | High — bootstrap step 4 |
| Tier detection (`T0`/`T1`) | Built | High — auto-detected on shell login |
| `shell/setup-wsl-boot.sh` (boot optimization) | Built | High — `--revert` supported; idempotent |
| PowerShell module install | Built | High — Pester-tested |
| Weekly WSL `.tar` snapshot rotation | Built | High |
| M-11 fleet-wide pre-push hook | Built | High — CI-asserted wiring |

### Known drift between source + deployment (per memory)

| Layer | Source (revkit `main`) | Deployed in Joshua's WSL |
|---|---|---|
| Drive mount label + path | `Sandbox` / `/mnt/sandbox` (post-revkit#13) | Still `Forge` / `/mnt/forge` (re-bootstrap pending) |
| Runtime tree | `shell/` (post-#63) | May still reference `wsl/` until re-bootstrap |
| Env var | `REVEALUI_SANDBOX` | `REVEALUI_FORGE` |

**Action:** re-bootstrap the deployed environment when convenient (`bash ~/.revealui/bootstrap.sh`). Tracked in the Owner Action Queue. Memory `project_forge_drive_role` documents the split.

---

## Composition with the rest of RevFleet

RevKit is the workstation. Other RevFleet products run on top of what RevKit provisions:

- **Contributor onboarding**: clone the repo → run `bootstrap.sh` (any of macOS / Linux / WSL2) → working studio environment.
- **Reproducibility**: every dev workstation builds from the same neutral configs; per-user values stay machine-local.
- **Pairs with RevVault**: RevKit sets up the age-identity mount path RevVault expects.
- **Pairs with RevCon**: bootstrap step 8 wires RevFleet Claude rules via `revcon/link.sh`.
- **Independent of RevealUI**: RevKit is a workstation toolkit, not a runtime dependency.

---

## Roadmap

Pre-1.0 per the fleet versioning convention. Promotion gated on real external consumers (other contributors using RevKit to bootstrap their own machines).

### Phase A — Single-developer bootstrap (DONE)

WSL workstation bootstrap for the founder's primary + secondary machines. Deployed environment runs from `~/.revealui`.

### Phase B — Cross-platform foundation (DONE, 2026-06)

Absorbs the old "Mac/Linux native bootstrap" goal plus the architecture pivot away from TOML profiles. Shipped via #62–#68:

- **#62** — `lib/platform.sh` OS detector + fixtures + CI.
- **#63** (B1) — runtime tree rename `wsl/` → `shell/`, `bashrc.d/` → `shellrc.d/`.
- **#64 / #65** (B2) — removed the TOML-profile / `scripts/render.sh` / `profiles/` / `templates/` subsystem in favor of neutral tracked configs + per-user `include.path`.
- **#66** — `rfc` runs native on macOS + Linux; `rf`/`rfclaude` reconciled.
- **#67** — chrome-bridge shell fragment gated to WSL-only.
- **#68** (B3) — universal `bootstrap.sh` cross-platform entry point.

(Adjacent hardening that rode the same window: CodeQL #69; with-secrets point-of-use secret scoping #71 / GAP-251.)

### Phase C — Repo-truth reconciliation (IN FLIGHT)

Make the repo describe shipped reality and converge on one entry point.

- [x] Reconcile `MASTER_PLAN.md` + `MASTER_SPEC.md` to the cross-platform reality (this lane).
- [x] De-brick `README.md` — remove the dead `profiles/` + `scripts/render.sh` instructions; lead with `bootstrap.sh`.
- [x] Single canonical entry point — `bootstrap-wsl.sh` → deprecation shim that execs `bootstrap.sh`.
- [x] Close the `bootstrap.sh` CI-coverage gap (repoint the M-11 wiring check at `bootstrap.sh`).

### Phase D — External-contributor onboarding (NEXT)

Reconciled successor to the old "Phase 2" (minus the now-dead profile-customization item).

- [ ] End-to-end `bootstrap.sh --dry-run` smoke test in CI on an **ubuntu + macOS matrix** (the cross-platform claim currently rests on `platform.sh` fixtures only; no real macOS runner exists).
- [ ] First-run hardening for non-founder machines (no hard-coded identity, graceful when no sandbox drive / no Windows host).
- [ ] Onboarding doc for the neutral-config + per-user-`include.path` model.

---

## Owner Action Queue

| Item | Unblocks |
|---|---|
| Re-bootstrap Joshua's deployed WSL (`bash ~/.revealui/bootstrap.sh`) to pick up `/mnt/sandbox` paths + the `shell/` rename | Closes the source-vs-deploy drift (operational, not a code phase) |
| Decide whether RevKit should be public on GitHub or stay studio-internal | Phase D (external onboarding) |

---

## See also

- [`docs/MASTER_SPEC.md`](./MASTER_SPEC.md) — surface area + configuration model
- [`docs/rfc-launcher.md`](./rfc-launcher.md) — the `rfc` secure Claude launcher
- [`docs/tier-capabilities.md`](./tier-capabilities.md) — T0/T1 capability matrix
- [`docs/agent-coordination.md`](./agent-coordination.md) — file-based workboard coord (alternative to RevDev daemon)
- [`docs/WSL-CheatSheet.txt`](./WSL-CheatSheet.txt) + [`docs/WSL-QuickReference.md`](./WSL-QuickReference.md) — WSL ops reference
- [`README.md`](../README.md) — quick start
- Fleet master index (`MASTER_INDEX.md` in the RevealUI Studio internal coordination hub) — fleet-level navigation
