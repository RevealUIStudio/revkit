# Dispositions (Grok pointer)

**Plane A owner:** `~/.claude/rules/disposition-actions.md`.

## Adapter summary

Safe: read/audit, feature branches, open PRs, review comments, gaps/specs.  
Needs named in-session owner auth: merge (esp. self/security), gate labels, force-push, delete remote branches, mutate repo settings.

When blocked: stop; list the one-line owner command. Do not rephrase around the block.

**Owner-action `gh` form (all sessions):** prefer short `-R owner/repo` (not
long `--repo`). Example:
`gh pr edit 2482 -R RevealUIStudio/revealui --add-label sec-review:approved`.
