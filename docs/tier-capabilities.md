# DevKit Tier Capabilities

## T0 — Base (Sandbox drive not mounted)

Everything on the C: drive works without the external drive.

| Capability | Status | Notes |
|------------|--------|-------|
| Shell environment | Available | bashrc.d fragments, aliases, PATH |
| Git + SSH | Available | Identity, signing, remote access |
| Node.js (fnm) | Available | Version managed via fnm |
| Age secrets | Available | Keys in `~/.age-identity/` |
| Chrome bridge | Available | `chrome` alias → Windows Chrome |
| `sandbox` CLI | Partial | `sandbox help/validate` work; `sandbox up` blocked |
| Docker services | Blocked | No persistent storage without Sandbox drive |
| Postgres / Redis | Blocked | Require T1 |
| Ollama | Blocked | Model weights stored on Sandbox drive |

## T1 — Full (Sandbox drive mounted at `/mnt/sandbox`)

Everything in T0, plus persistent infrastructure services.

| Capability | Status | Notes |
|------------|--------|-------|
| All T0 capabilities | Available | — |
| `sandbox up/down` | Available | Starts/stops Docker Compose services |
| Postgres (port 5433) | Available | Data in `/mnt/sandbox/databases/postgres` |
| Redis (port 6380) | Available | Data in `/mnt/sandbox/databases/redis` |
| Ollama (port 11434) | Available | `sandbox up --ai`; models in `/mnt/sandbox/models` |
| Build/package caches | Available | `/mnt/sandbox/cache` |
| `sandbox validate` | Full | Runs all 21 checks including container health |

## Environment Variables

| Variable | T0 | T1 |
|----------|----|----|
| `DEVKIT_TIER` | `T0` | `T1` |
| `REVEALUI_ROOT` | Set (C: drive) | Set (C: drive) |
| `REVEALUI_SANDBOX` | `/mnt/sandbox` | `/mnt/sandbox` |
| `REVEALUI_SANDBOX_MOUNTED` | Unset | `1` |
| `SANDBOX_DATABASE_URL` | Set (connection string) | Set (connection string) |
| `SANDBOX_REDIS_URL` | Set (connection string) | Set (connection string) |

## Tier Transitions

Tiers are detected automatically on shell login by `00-base.sh`:

- **T0 → T1**: Run `mount-sandbox-drive.sh` (or `Mount-WSLDev` from PowerShell), then open a new shell
- **T1 → T0**: Unmount the Sandbox drive or disconnect the USB, then open a new shell

The `sandbox validate` command verifies the current tier is consistent.
