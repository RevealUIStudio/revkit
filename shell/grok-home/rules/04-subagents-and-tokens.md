# Subagents and token economy (Grok pointer)

**Token economy owner:** `~/.claude/rules/token-economy.md` (+ native GAP-362).  
**Model allocation:** `08-model-allocation.md` → work classes Design/Build/Verify/Deploy.  
**Routing:** use Grok subagent types (`explore`, `plan`, `senior-architect`, `implementer`, `reviewer`, `mechanic`).

Map roughly: plan/senior-architect → **Design**; implementer → **Build**;  
reviewer → **Verify**; mechanic → light **Build**. **Deploy** is promote +  
runtime, not a subagent type.

## Adapter summary

- One well-scoped subagent over many tiny ones.
- Multi-file implementer → `isolation: "worktree"`.
- Never poll harness-notified background work.
- Prefer native file tools over shell find/grep when available.
