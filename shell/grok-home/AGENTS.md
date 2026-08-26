# Grok — RevealUI Studio (professional)

Pointer-thin machine home. Shared hardlines are not authored here.
This file is **RevKit SSOT** (`shell/grok-home/AGENTS.md`). `rfg` and
`bootstrap.sh` copy it onto Grok's vendor attach (`$GROK_HOME/AGENTS.md`).
Do not edit `$HOME/.grok/AGENTS.md` by hand.

- **In scope:** RevealUI Studio work under `~/revfleet/`.
- **Out of scope:** personal projects under Windows PowerShell / `~/archive/`.
- **Identity:** RevealUI Studio GitHub noreply (`git config user.email`). Never `founder@revealui.com`.

## Load order

1. Preamble pointers: `$GROK_HOME/rules/` (00-09), deployed by RevKit from
   `shell/grok-home/rules/`. Do not full-copy Claude hardlines into this file.
2. When cwd is a product, Grok also loads `<repo>/.grok/rules/` (harnesses
   materialize, preamble tier 1). Shared policy SSOT is `.revealui/content/`.
3. When cwd has `.revealui/manager.json`: that file + `.revealui/content/`, then TRACKER.
4. Product I/O via RevealUI MCP (`rfg`). Secrets via revvault only.

`[compat.claude] rules = false` and `agents = false`. Do not re-enable rules. Hooks, skills, and mcps stay on.

Policy owners live in `@revealui/harnesses` → `.revealui/content/`. Claude Code keeps `~/.claude/` untouched.

## Stack

TypeScript strict, ES modules, pnpm 10, Turborepo, Biome, Vitest, Tailwind v4, Nix + direnv.

```
feature/* ──PR──▶ test ──PR──▶ main
```

```bash
rfg revealui
pnpm dev:app
pnpm gate
pnpm validate:claims
```

MCP attach: `rfg` (RevKit). Vault path `revealui/dev/mcp/cli-token`. Never put device tokens in git or config.

## Keepers

RevKit `shell/grok-home/` (this file + 00-09), PreToolUse helper via `rfg` attach, `permission_mode = auto`.

Do not invent parallel queues under `~/.grok`. Merges, gate labels, force-push, and repo-setting mutations need named in-session owner auth.
