# Dual harness — Claude + Grok (pointer)

**Status:** Grok orientation only. Shared policy is **not** re-authored here.

**Architecture:** `.jv` ADR `2026-07-21-harness-policy-runtime-launch-planes`  
**Native center:** RevealUI MCP + `@revealui/harnesses` content + TRACKER — adapters **communicate with** that layer (GAP-406).

## Layout

| Concern | Single owner | Grok duty |
|---------|--------------|-----------|
| Shared hardlines | `@revealui/harnesses` definitions → `.revealui/content/` | Project `.grok/rules/` (preamble tier 1). `[compat.claude] rules = false` — do not ingest the Claude dump |
| Private SDLC | `.jv` | Load when cwd under revfleet |
| Product I/O | RevealUI MCP (`rfg`) | Call MCP; no side-channel tools |
| Day-to-day backlog | `.jv/docs/TRACKER.md` | Open TRACKER first |
| Grok-only ops | RevKit `shell/grok-home/` | Deployed to `$GROK_HOME/rules` (attach cache). Do not author under `$HOME/.grok` |

## Forbidden

- Full-copy a hardline into Grok + Claude + project rules in one change.
- Invent parallel queues under `~/.grok`.

**Durable solutions:** `~/.claude/rules/durable-solutions.md` + Grok `07-durable-solutions.md` pointer.
