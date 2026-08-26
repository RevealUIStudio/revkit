# Secrets and safety (Grok pointer)

**Plane A owner:** `~/.claude/rules/secrets.md`.  
**ADR:** `.jv` `docs/decisions/2026-08-05-stream-safe-secrets.md` (GAP-468).

## Adapter summary

- Secrets only via revvault. Never paste values into chat or tool args.
- **Stream-safe default:** `revvault run --env KEY=path -- cmd` or
  `with-secrets <ns…> -- cmd`. Paths only on the command line.
- **Forbidden:** `$(revvault get …)` in Bash (PreToolUse denies); secret-bearing
  `--database-url 'postgresql://…@…'`.
- **Break-glass full key:** vault-private terminal (OBS excluded) with
  `REVVAULT_ALLOW_PRINT=1` / `vault-private`, then `revvault get --full` or
  `--clip`.
- Fail loud if missing; name the revvault path only.
- Respect PreToolUse security scanner blocks (Claude-compat hooks).
