# Agent Coordination

Multi-agent coordination for Claude Code sessions, powered by a shared workboard file.

## Status (2026-04-23)

**This file-based workboard is an *alternative* coordination mode, not the fleet's default.**

The authoritative RevFleet setup has moved to **RPC-only coordination via the RevDev daemon** — see `~/revfleet/.claude/rules/hooks-architecture.md` in the fleet workspace. In that model there is no `.claude/workboard.md`, no lock file, and no file-based "Active Sessions" table; coordination flows through the daemon's Unix socket, and `isDaemonAlive()` is a fast `fs.statSync` on the socket with no ping.

The templates and hooks documented below still ship with revkit for two legitimate use cases:

1. **Lightweight bootstrap** — a project that doesn't run the RevDev daemon (and doesn't need its memory/RPC features) can still get cross-session conflict prevention and a handoff history from a file-based workboard.
2. **Offline / minimal-dep setup** — no Rust toolchain, no socket, no daemon process. Just Node + a markdown file.

If you're bootstrapping a RevFleet product, skip the workboard hooks and wire the RevDev daemon instead. If you're bootstrapping a greenfield or one-off project and want a minimal multi-agent coordination layer, read on.

## What the Workboard Is

The workboard is a Markdown file (`<project>/.claude/workboard.md`) that tracks which Claude Code agents are active, what each is working on, and which files each has touched. It serves three purposes:

1. **Conflict prevention** — agents can see which files other agents are editing and avoid collisions.
2. **Context injection** — on every prompt, each agent receives a summary of what other agents are doing (via stdout injection).
3. **Session history** — when an agent stops, its task summary moves to a "Recent" section for handoff context.

The workboard uses a standard Markdown table format that both humans and hooks can read/write:

```markdown
## Active Sessions

| id | env | started | task | files | updated |
|----|-----|---------|------|-------|---------|
| agent-laptop | agent-laptop | 2026-03-25T14:30Z | refactoring auth | src/auth.ts | 2026-03-25T14:35Z |
```

## Hook Lifecycle

Four hooks manage the workboard automatically. No manual intervention required.

```
SessionStart          UserPromptSubmit         PostToolUse (Edit/Write)     Stop
    |                       |                          |                      |
    v                       v                          v                      v
session-start.js     workboard-inject.js       workboard-update.js        stop.js
    |                       |                          |                      |
    +- Shell init           +- Read stdin prompt       +- Parse file_path     +- Validate hooks
    +- Validate hooks       +- Update own task col     +- Update files col    +- Uncommitted warn
    +- Register row         +- Output other agents     +- Prune stale rows    +- Remove own row
    +- Prune stale rows                                                       +- Write to Recent
                                                                              +- Handoff warning
```

### 1. `session-start.js` (SessionStart)

Runs once when a Claude Code session begins:
- Writes shell init commands to `CLAUDE_ENV_FILE` (PATH, direnv)
- Validates all hook scripts with `node --check`
- Registers a new row in the workboard (or updates timestamp if row already exists)
- Prunes sessions that haven't updated in 4 hours (crashed agents)
- Creates the workboard from `workboard.template.md` if it doesn't exist yet

### 2. `workboard-inject.js` (UserPromptSubmit)

Runs on every user message:
- Reads the user prompt from stdin (JSON, truncated to 80 chars)
- Updates the agent's own `task` and `updated` columns
- Reads other agents' rows and outputs a summary to stdout, which Claude Code injects as context before the response

### 3. `workboard-update.js` (PostToolUse — Edit/Write only)

Runs after every file edit:
- Parses `CLAUDE_TOOL_INPUT` for the `file_path`
- Adds the relative file path to the agent's `files` column (deduped, last 5 kept)
- Updates the `updated` timestamp
- Prunes stale rows opportunistically

### 4. `stop.js` (Stop)

Runs when a Claude Code session ends:
- Re-validates all hook scripts
- Warns about uncommitted git changes
- Removes the agent's row from the Active Sessions table
- If the agent did work (task was not "(starting)"), writes a summary to the Recent section
- Warns about in-flight files for handoff
- Cleans up the session ID cache

## Setup

### 1. Render the Hook Templates

The hooks are DevKit templates with `{{PROJECT_DIR}}` and `{{PROJECT_NAME}}` placeholders. Render them alongside your other templates:

```bash
./scripts/render.sh --config config.toml --output ~/.revealui
```

This renders the hooks to `~/.revealui/hooks/`. Copy them to your Claude Code hooks directory:

```bash
cp -r ~/.revealui/hooks/* ~/.claude/hooks/
```

Or render directly to the hooks directory:

```bash
./scripts/render.sh --config config.toml --output ~/.claude --templates templates/hooks
```

### 2. Configure `settings.json`

Wire the hooks in `~/.claude/settings.json` (or `<project>/.claude/settings.json` for project-scoped hooks). Each hook maps to a specific Claude Code lifecycle event:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "node \"$HOME/.claude/hooks/session-start.js\""
      }
    ],
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "node \"$HOME/.claude/hooks/workboard-inject.js\""
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "node \"$HOME/.claude/hooks/workboard-update.js\"",
        "matcher": "Edit|Write"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "node \"$HOME/.claude/hooks/stop.js\""
      }
    ]
  }
}
```

### 3. Create the Workboard

The `session-start.js` hook auto-creates the workboard from `workboard.template.md` on first run. You can also create it manually:

```bash
mkdir -p ~/projects/MyApp/.claude
cp ~/.claude/hooks/workboard.template.md ~/projects/MyApp/.claude/workboard.md
```

Add the workboard to `.gitignore` — it contains transient session state:

```gitignore
.claude/workboard.md
.claude/workboard.md.tmp.*
.claude/workboard.lock
```

## Agent Identity

Each agent gets an identity string used as its workboard row key. The identity module (`lib/identity.js`) uses a 3-tier cascade:

1. **`CLAUDE_AGENT_ROLE` env var** — set this explicitly when running multiple agents (e.g., via tmux windows with different env vars).
2. **Session cache** — written to `/tmp/devkit-session-<ppid>.id` on first detection; reused for 8 hours.
3. **Hostname fallback** — `agent-<hostname>` when no other identity is available.

For multi-agent setups, set `CLAUDE_AGENT_ROLE` per terminal:

```bash
# Terminal 1
export CLAUDE_AGENT_ROLE="agent-frontend"
claude

# Terminal 2
export CLAUDE_AGENT_ROLE="agent-backend"
claude

# Terminal 3
export CLAUDE_AGENT_ROLE="agent-infra"
claude
```

## Concurrency and Locking

All workboard writes use atomic file locking (`O_EXCL` flag on a `.lock` file):
- Dead-lock detection: if the lock holder's PID is no longer alive, the lock is stolen.
- Timeouts: 2 seconds for session-start/stop/workboard-update, 1 second for workboard-inject (high-frequency).
- Writes use tmp-file-then-rename for atomicity (rename on the same filesystem is atomic on Linux).
- Stale rows (no update in 4 hours) are pruned opportunistically.

## Profiles and Team Sizes

### Solo Developer

Single agent, no coordination needed. The hooks still work — the workboard just has one row, and the inject hook outputs nothing. Useful as a session history log.

Use `profiles/solo-dev.toml`:

```toml
[project]
project_dir = "~/projects/MyApp"
project_name = "MyApp"
```

### Small Team (2-3 Agents)

Set `CLAUDE_AGENT_ROLE` per terminal. All agents share the same workboard file. No additional configuration needed beyond the hooks.

Use `profiles/full-stack.toml` or `profiles/team.toml`:

```toml
[project]
project_dir = "~/projects/MyApp"
project_name = "MyApp"
```

Run agents in separate terminals:

```bash
# tmux window 1
CLAUDE_AGENT_ROLE=agent-frontend claude
# tmux window 2
CLAUDE_AGENT_ROLE=agent-backend claude
```

### Larger Teams

For 4+ agents, consider:
- Keeping the workboard file in a shared location (e.g., a git-ignored file on a network mount)
- Setting distinct `CLAUDE_AGENT_ROLE` values per team member or per task
- Monitoring the Recent section for handoff context between shifts

## Troubleshooting

**Workboard not updating**: Check that the hooks are wired in `settings.json` and that the `{{PROJECT_DIR}}` placeholder was correctly rendered. Run `node --check` on each hook script.

**Stale rows persisting**: Rows are pruned when any hook acquires the lock. If no hooks are running, manually delete the stale rows. Never edit the workboard while an agent is active — use the Stop hook or close the agent first.

**Lock file stuck**: If `.claude/workboard.lock` exists but no agent is running, delete it manually:

```bash
rm ~/projects/MyApp/.claude/workboard.lock
```

**Identity collisions**: Two agents with the same `CLAUDE_AGENT_ROLE` will share a workboard row. Use distinct role names for each concurrent agent.
