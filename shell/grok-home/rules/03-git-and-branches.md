# Git and branches (Grok pointer)

**Plane A owner:** `~/.claude/rules/git.md` (Claude-compat). Do not full-copy.

## Adapter summary

- Identity: `RevealUI Studio <43050008+joshua-v-dev@users.noreply.github.com>` (noreply only).
- Cut new work from `origin/test` (or `origin/main` if no `test`). Never from a feature branch.
- PR target: `test`. Promote `test` → `main` separately.
- Launch: `rfg revealui --worktree=<label>` injects `--ref test` when omitted.
- Worktrees: see `06-worktree-isolation.md` pointer.
- **`gh` form:** always prefer `-R owner/repo` over `--repo` in owner actions and agent scripts (see disposition-actions).

Verify: `git config --show-origin --get user.email`
