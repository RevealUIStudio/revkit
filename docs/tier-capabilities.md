# DevKit Tier Capabilities

## T0 — Base (Forge drive not mounted)

Everything on the C: drive works without the external drive.

| Capability | Status | Notes |
|------------|--------|-------|
| Shell environment | Available | bashrc.d fragments, aliases, PATH |
| Git + SSH | Available | Identity, signing, remote access |
| Node.js (fnm) | Available | Version managed via fnm |
| Age secrets | Available | Keys in `~/.age-identity/` |
| Chrome bridge | Available | `chrome` alias → Windows Chrome |
| `forge` CLI | Partial | `forge help/validate` work; `forge up` blocked |
| Docker services | Blocked | No persistent storage without Forge drive |
| Postgres / Redis | Blocked | Require T1 |
| Ollama | Blocked | Model weights stored on Forge drive |

## T1 — Full (Forge drive mounted at `/mnt/forge`)

Everything in T0, plus persistent infrastructure services.

| Capability | Status | Notes |
|------------|--------|-------|
| All T0 capabilities | Available | — |
| `forge up/down` | Available | Starts/stops Docker Compose services |
| Postgres (port 5433) | Available | Data in `/mnt/forge/databases/postgres` |
| Redis (port 6380) | Available | Data in `/mnt/forge/databases/redis` |
| Ollama (port 11434) | Available | `forge up --ai`; models in `/mnt/forge/models` |
| Build/package caches | Available | `/mnt/forge/cache` |
| `forge validate` | Full | Runs all 21 checks including container health |

## Environment Variables

| Variable | T0 | T1 |
|----------|----|----|
| `DEVKIT_TIER` | `T0` | `T1` |
| `REVEALUI_ROOT` | Set (C: drive) | Set (C: drive) |
| `REVEALUI_FORGE` | `/mnt/forge` | `/mnt/forge` |
| `REVEALUI_FORGE_MOUNTED` | Unset | `1` |
| `FORGE_DATABASE_URL` | Set (connection string) | Set (connection string) |
| `FORGE_REDIS_URL` | Set (connection string) | Set (connection string) |

## Tier Transitions

Tiers are detected automatically on shell login by `00-base.sh`:

- **T0 → T1**: Run `mount-forge-drive.sh` (or `Mount-WSLDev` from PowerShell), then open a new shell
- **T1 → T0**: Unmount the Forge drive or disconnect the USB, then open a new shell

The `forge validate` command verifies the current tier is consistent.
