# RevFleet map (Grok)

Work root: `~/revfleet/`.

## Products

| Repo | One-liner |
|------|-----------|
| **revealui** | Agentic business runtime: 4 apps + ~28 packages. Five primitives: people, content, offers, payments, agents. |
| **.jv** | Private brain: MASTER_PLAN, gaps, lanes, CURRENT-HANDOFF, workboard. Not a public product. |
| **revdev** | Studio (Tauri) + Console (Go TUI) + harness daemon (JSON-RPC). |
| **revvault** | Age-encrypted secret vault. Source of truth for every fleet secret. |
| **revcon** | Symlinked editor configs + agent rules (`./link.sh`). |
| **revskills** | SKILL.md library for Claude/Cursor/Grok. |
| **revforge** | Stamps branded RevealUI Fleet kits for enterprise. |
| **revkit** | WSL-first dev environment bootstrap. |
| **agency** | revealuistudio.com (consumes `@revealui/*` via npm). |
| **status** | Upptime status page. |
| **demo-offline-sync** | ElectricSQL offline demo. |

## Naming

- **RevFleet** = umbrella for all Studio software.
- **RevealUI Fleet** = customer self-host kit.
- **RevForge** = operator stamping tool.
- Avoid bare "Fleet", "Suite", or "RevealUI Studio Fleet".

## When starting cold

1. Confirm cwd under `~/revfleet/`.
2. If **`./.revealui/manager.json`** exists, open it first (project policy authority; equal vendors).
3. Open **`.jv/docs/TRACKER.md`** second (free surfaces for every harness). Without manager, TRACKER is the primary board.
4. For product behavior claims: read code first (`code-over-docs`).
5. Strategy / session delta only if needed: `MASTER_PLAN.md` + `handoffs/CURRENT-HANDOFF.md`.
6. For secrets: `revvault`, never paste values into chat.

## Shared archive (operator machine)

Cold history lives at `~/revfleet/archive/` (not inside product git).  
See `~/revfleet/archive/README.md`. Env: `REVFLEET_ARCHIVE`, `AUDIT_RUN_ROOT`.
Distinct from `~/archive/` (retired personal/iced projects).

## Single fleet tracker

Day-to-day backlog for **all** models/providers: `~/revfleet/.jv/docs/TRACKER.md`  
(regenerate: `node scripts/initiatives-render.js`). Do not invent parallel queues under `~/.grok`.
