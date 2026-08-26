# Durable solutions (Grok pointer)

**Control layer:** RevealUI `@revealui/harnesses` rule `durable-solutions`
(preamble tier 1) + `revealui-harnesses hotfix`. Project materialization:
`.revealui/content/rules/durable-solutions.md`. Do **not** full-copy the body.

## Short form (every Grok session)

1. **Durable only** — fix the owning primitive. Prefer refuse over temporary patches.
2. **Never propose workarounds** — not in chat, code, handoffs, or walks.
   No "until deploy…", "for now…", alternate logins, env-only recipes, or
   parallel paths that leave the failure class open.
3. **When blocked:** name the durable dependency (PR / deploy / owner disposition /
   CI outage). List only durable next actions. Waiting is OK; substitute recipes are not.
4. **Hotfix:** only if the owner explicitly accepts registered debt the same turn:
   `revealui-harnesses hotfix register --title … --symptom … --temporary … --durable …`
   (adapter: `node ~/.claude/scripts/hotfix.js …`)
5. Convert: `revealui-harnesses hotfix resolve <id> --pr <url>`
6. Audit: `revealui-harnesses hotfix audit [path]`

Store: `~/.local/share/revealui/hotfixes/manifest.json` (not vendor homes).

Sibling: `temp-scripts.md`. GAP-405. Owner 2026-08-06: no-workaround hardline.
