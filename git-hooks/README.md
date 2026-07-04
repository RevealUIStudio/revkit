# RevealUI Studio — Centralized Git Hooks

This directory is the deploy target for `git config --global core.hooksPath`.
Every git operation in a dev environment provisioned by revkit's bootstrap
runs these hooks unless a per-repo local config overrides `core.hooksPath`
(e.g. revealui's own Husky setup writes `core.hooksPath = .husky/_` locally
during `pnpm install`, taking precedence over the global value).

## Provenance

These hooks are installed as part of revkit's dev-environment bootstrap so that
branch-pipeline discipline (PR-only flow; no force-push or unsigned commits on
protected branches) is enforced consistently on every provisioned machine.
Installing them centrally through `core.hooksPath` — rather than per-clone —
keeps the policy uniform and makes it part of the standard setup rather than a
per-repo afterthought.

## Hooks

| Hook       | Enforces                                                                 |
|------------|--------------------------------------------------------------------------|
| `pre-push` | Branch-pipeline discipline (direct-push / force-push / unsigned-commit guards on protected branches).  |

### `pre-push` rules

For pushes to `refs/heads/main` and `refs/heads/test` (the fleet's protected
branches; mirrors the public-repo branch-protection on RevealUIStudio/revealui):

1. **Direct push rejected.** Land via PR through `feature/<topic>` → `test` → `main`.
2. **Force-push rejected.** No rewriting shared history.
3. **Unsigned commits rejected.** Defense-in-depth with existing signed-commit setup.

For `refs/heads/feature/*` and other non-protected branches:

- Force-push allowed (rebase + cleanup are legitimate workflows).
- Unsigned commits allowed.

For tag pushes and `refs/remotes/*` pushes: not policed.

### Per-repo escape hatch

Some repos legitimately need direct-to-main (docs-only, owner-only) or operate
outside the fleet branch pipeline. To opt out:

```bash
cd /path/to/that/repo
git config revealui.hooks.no-protection true
```

The flag is **per-repo local** (never global, never system) and visible in
`git config --list --local` for audit. Engaging the flag prints a loud warning
on every push and **does NOT bypass** the force-push or signed-commit checks
on protected branches — only the direct-push rule. To re-enable:

```bash
git config --unset revealui.hooks.no-protection
```

## Deployment

Both platforms are wired by `bootstrap.sh` (which auto-detects WSL via
`lib/platform.sh`; `bootstrap-wsl.sh` is now a thin deprecation shim that execs
`bootstrap.sh`). The deployment differs by platform:

**Linux / WSL** — `bootstrap.sh` copies an LF-normalized `pre-push` into
`~/.config/revkit/git-hooks/` and points `core.hooksPath` there:

```bash
git config --global core.hooksPath "$HOME/.config/revkit/git-hooks"
```

A normalized copy (not the in-repo file) is used because a `core.hooksPath`
aimed at the checkout would run a CRLF-corrupted hook if the working tree ever
carried CRLF endings. **Consequence:** on Linux/WSL, editing `pre-push` in the
revkit checkout does NOT take effect until the next `bootstrap.sh` run — a
`git pull` alone is not enough. Re-running bootstrap is idempotent and safe.

**Windows** — `bootstrap.ps1` points `core.hooksPath` directly at THIS in-repo
directory (the `.gitattributes` `git-hooks/* text eol=lf` rule keeps the tracked
hook LF-clean, so no copy is needed):

```powershell
git config --global core.hooksPath "$revealRoot\git-hooks"
```

On Windows the hook tracks the checkout live — a `git pull` of revkit is enough.

### Conflict handling

Bootstrap reads `git config --global --get core.hooksPath` before writing:

| Existing value                       | Behavior                                                             |
|--------------------------------------|----------------------------------------------------------------------|
| unset                                | Set to this directory.                                               |
| already pointing at this directory   | No-op (idempotent re-run).                                           |
| pointing elsewhere                   | **Fail loudly.** Owner-decision: unset existing, then re-run bootstrap. |

The "fail loudly" path is intentional. Silent overwrite would clobber another
tool's setup; silent skip would silently disable hook enforcement. Neither is
acceptable — the user picks.

## CI

`.github/workflows/ci.yml` includes a `git-hooks-validate` job that runs
`bash -n` + ShellCheck on every file in this directory. Hooks are NOT exercised
in CI (no real push surface) — only their parse + lint cleanliness is gated.

## Hardline conventions honored

- **No regex authored.** All branch-ref classification uses bash `==` string
  ops + parameter-expansion prefix-strip + `case` patterns. Force-push
  detection uses `git merge-base --is-ancestor` (git plumbing), not regex.
- **No tactical shortcuts.** Hook is universal across all repos in the dev env.
  Failure mode is loud + clear remediation pointer. Per-repo opt-out is the
  ONLY escape and it's auditable.
- **No per-clone hook copies.** Deployment is via global `core.hooksPath` — on
  Windows pointing at this directory, on Linux/WSL at a single bootstrap-managed
  normalized copy under `~/.config/revkit/git-hooks` (one per machine, shared
  across all clones — not per-clone). Per-clone `.git/hooks/pre-push` is the
  anti-pattern the spec rejects (per-machine fragility — machine A has the hook,
  machine B doesn't).
- **Read-only on existing system files.** The hook only reads git plumbing
  output; it mutates nothing.
