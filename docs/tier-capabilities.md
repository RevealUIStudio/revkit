# DevKit Tier Capabilities

## T0 — Base (Studio drive not mounted)

Everything on the C: drive works without the external drive.

| Capability | Status | Notes |
|------------|--------|-------|
| Shell environment | Available | bashrc.d fragments, aliases, PATH |
| Git + SSH | Available | Identity, signing, remote access |
| Node.js (fnm) | Available | Version managed via fnm |
| Age secrets | Available | Keys in `~/.age-identity/` |
| Chrome bridge | Available | `chrome` alias → Windows Chrome |
| `studio` CLI | Partial | `studio help/validate` work; `studio up` blocked |
| Docker services | Blocked | No persistent storage without Studio drive |
| Postgres / Redis | Blocked | Require T1 |
| Ollama | Blocked | Model weights stored on Studio drive |

## T1 — Full (Studio drive mounted at `/mnt/studio`)

Everything in T0, plus persistent infrastructure services.

| Capability | Status | Notes |
|------------|--------|-------|
| All T0 capabilities | Available | — |
| `studio up/down` | Available | Starts/stops Docker Compose services |
| Postgres (port 5433) | Available | Data in `/mnt/studio/databases/postgres` |
| Redis (port 6380) | Available | Data in `/mnt/studio/databases/redis` |
| Ollama (port 11434) | Available | `studio up --ai`; models in `/mnt/studio/models` |
| Build/package caches | Available | `/mnt/studio/cache` |
| `studio validate` | Full | Runs all 21 checks including container health |

## Environment Variables

| Variable | T0 | T1 |
|----------|----|----|
| `DEVKIT_TIER` | `T0` | `T1` |
| `REVEALUI_ROOT` | Set (C: drive) | Set (C: drive) |
| `REVEALUI_STUDIO` | `/mnt/studio` | `/mnt/studio` |
| `REVEALUI_STUDIO_MOUNTED` | Unset | `1` |
| `STUDIO_DATABASE_URL` | Set (connection string) | Set (connection string) |
| `STUDIO_REDIS_URL` | Set (connection string) | Set (connection string) |

## Tier Transitions

Tiers are detected automatically on shell login by `00-base.sh`:

- **T0 → T1**: Run `mount-studio-drive.sh` (or `Mount-WSLDev` from PowerShell), then open a new shell
- **T1 → T0**: Unmount the Studio drive or disconnect the USB, then open a new shell

The `studio validate` command verifies the current tier is consistent.
