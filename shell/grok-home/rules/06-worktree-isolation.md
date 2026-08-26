# Worktree isolation (Grok pointer)

**Status:** Grok pointer only. Full hardline lives in Plane A — do not mirror the body here.

**Owner (Plane A):**

- `~/.claude/rules/git.md` (branch base from `origin/test`)
- Fleet planning coordination rule, Worktree Discipline section
- Enforcement: `~/.claude/hooks/dirty-checkout-guard.js` (Claude + Grok PreToolUse)

## Adapter summary (ops only)

1. Multi-step product work → `~/revfleet/.wt/<name>` (or `rfg … --worktree=`), never dirty branch-switch on the shared checkout.
2. Prefer `isolation: "worktree"` for multi-file implementer subagents.
3. If blocked by dirty checkout guard: commit/push, move to a worktree, or intentional `ALLOW_DIRTY_CHECKOUT=1` only when deliberate.

Do not re-author the full hardline in this file. Edit the Plane A owner, then thin consumers.
