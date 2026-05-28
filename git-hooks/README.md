# RevealUI Studio — Centralized Git Hooks (M-11)

This directory is the deploy target for `git config --global core.hooksPath`.
Every git operation in a dev environment provisioned by revkit's bootstrap
runs these hooks unless a per-repo local config overrides `core.hooksPath`
(e.g. revealui's own Husky setup writes `core.hooksPath = .husky/_` locally
during `pnpm install`, taking precedence over the global value).

## Provenance

Implements **M-11** from the fleet-security-hardening meta-durability lane —
the class-killer for "absent server-side branch protection on private repos"
(T0-15). GitHub Free rejects branch-protection API calls on private repos
and the owner has rejected the GitHub Team upgrade (2026-05-16). The next-best
durable enforcement is a uniformly-installed local hook that can't be
sidestepped per-machine because deployment is part of the dev-env bootstrap.

See the internal fleet-security-hardening lane (meta-durability-fixes §M-11)
for the full design rationale and the anti-patterns explicitly rejected.

## Hooks

| Hook       | Enforces                                                                 |
|------------|--------------------------------------------------------------------------|
| `pre-push` | Branch-pipeline discipline on private repos lacking GitHub protection.  |

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

Linux/WSL — `bootstrap-wsl.sh` step 8 runs:

```bash
git config --global core.hooksPath "$SCRIPT_DIR/git-hooks"
```

Windows — `bootstrap.ps1` step 6 runs:

```powershell
git config --global core.hooksPath "$revealRoot\git-hooks"
```

Both write the path as the absolute location of THIS directory inside the
revkit checkout. There is no copy step: updates to the hook land on the next
`git pull` of revkit, without re-running bootstrap. Re-running bootstrap is
idempotent and safe.

### Conflict handling

Bootstrap reads `git config --global --get core.hooksPath` before writing:

| Existing value                       | Behavior                                                             |
|--------------------------------------|----------------------------------------------------------------------|
| unset                                | Set to this directory.                                               |
| already pointing at this directory   | No-op (idempotent re-run).                                           |
| pointing elsewhere                   | **Fail loudly.** Owner-decision: unset existing, then re-run bootstrap. |

The "fail loudly" path is intentional. Silent overwrite would clobber another
tool's setup; silent skip would silently disable M-11 enforcement. Neither is
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
- **No per-clone hook copies.** Deployment is via global `core.hooksPath`
  pointing at this directory. Per-clone `.git/hooks/pre-push` is the anti-
  pattern the spec explicitly rejects (per-machine fragility — machine A has
  the hook, machine B doesn't).
- **Read-only on existing system files.** The hook only reads git plumbing
  output; it mutates nothing.
