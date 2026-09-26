# Client-name public GitHub defense

Defense in depth so buyer, network Consultation, end-client, and agency-client identifiers never appear on **public** GitHub. This document ships in revkit. It must never list real watchlist terms.

Do not use an em dash (U+2014) in this document or in public copy. Use a hyphen, a colon, or parentheses instead.

## Problem

Public org surfaces (PR titles and bodies, comments, tip code, fixtures, commit messages, CI workflows) can accumulate real buyer or end-client identifiers from Desk pastes, Build prompts, cloud-agent fixtures, or share-seed slugs. Search indexes lag. Editable hits can be scrubbed. Tip code needs a forward PR. Merged history is owner-gated.

## Fleet scope

Applies to the **whole RevealFleet** (every bot and every public RevealUIStudio repo). Soft-enforce owner: REV. CEO runs Layer A daily org audit and maintains the private inventory. Every bot applies Layer C on Build pastes, cloud-agent prompts, PR titles and bodies, commits, and fixtures.

## Layers A-D

### Layer A - Bot daily org audit

Grok Bot routine plus skill `client-name-public-github-audit` scans the studio public org via GitHub API: PRs, issues, comments, code tips, recent commits. Scrubs editable public text to generic labels. Inventories residuals privately on the box. Stays quiet when clean (per routine).

Private inventory home: `/workspace/client-name-github-audit/` (box only; not a public git tree).

### Layer B - Local / CI gate (two scanners)

Layer B is two gates that stay side by side. Neither replaces the other.

| Scanner | What it matches | Where the terms live |
|---------|-----------------|----------------------|
| `scripts/check-client-leaks.sh` | Long-lived literal denylist | Hardcoded in that script. Stays in git. CI: `.github/workflows/check-client-leaks.yml` |
| `scripts/check-no-client-names.sh` | Operator watchlist terms | Gitignored local file, or a CI secret file path, or `CLIENT_NAME_PATTERNS`. Never committed |

`scripts/check-no-private-leaks.sh` is a different companion. It catches paths, hostnames, license-shaped strings, and machine homes. It does not catch people or business identifiers.

Use the hardcoded scanner for literals that must keep failing closed on every public CI run, with no secret mounted. Use the watchlist gate for terms that must not appear in this public repo at all, including inside a script. Do not move watchlist terms into `check-client-leaks.sh` just to "activate" them, and do not delete the hardcoded `PATTERNS` array because the watchlist gate exists.

Public repos must never contain the real watchlist. The watchlist gate loads patterns from the first found of:

1. `$CLIENT_NAME_WATCHLIST_FILE`
2. `.client-name-watchlist.local` under the repo root
3. `$CLIENT_NAME_PATTERNS` (newline or `|` separated)

If no watchlist is present, the script prints a WARN and exits 0 (gate inactive) so public CI without a secret does not false-fail. Layer A still runs daily. Set `CLIENT_NAME_WATCHLIST_REQUIRED=1` to force exit 2 when the watchlist is missing (strict laptop or private CI).

Exit codes: 0 clean or inactive, 1 violation, 2 setup error. `LEAK_JSON=1` prints a one-line JSON object.

Example template (placeholders only, such as `buyer_example` and `agency_client_example`): `templates/client-name-watchlist.example`. The `templates/` directory here is that sample. It is not the old config-render templates tree.

`.github/workflows/check-no-client-names.yml` runs the watchlist gate with no secret mounted, so the job is inactive and exits 0. To require a watchlist later, without committing terms:

1. Store the watchlist text in a GitHub Actions secret. This repo does not name or create that secret.
2. In the job, write the secret to a file outside the checkout (for example under `$RUNNER_TEMP`) with mode `0600`.
3. Export `CLIENT_NAME_WATCHLIST_FILE` to that path.
4. Optionally export `CLIENT_NAME_WATCHLIST_REQUIRED=1` so a missing file fails the job (exit 2) instead of staying inactive.

Do not put term text in the workflow YAML.

### Layer C - Soft locks

Build prompts, cloud-agent instructions, and PR templates use **generic labels only**:

- buyer
- network Consultation
- end-client
- Studio Consultation invoice
- demo (share seed slug)
- agency client

Never paste Desk or CRM person or company names into public PR text or fixtures destined for public remotes.

### Layer D - Inventory loop

Rolling `INVENTORY.md` under the private box audit home, severity P0-P3, guardrail gaps, until public hits stay at 0.

## Severity

| Level | Meaning |
|-------|---------|
| P0 | Editable public PR / issue / comment |
| P1 | Tip code / fixtures on a public branch |
| P2 | Orphaned history / force-pushed SHA |
| P3 | Private repo only |

## What must never be committed publicly

- Real watchlist terms (person, company, end-client business, private slugs)
- `.client-name-watchlist.local` (gitignored)
- The live watchlist file under the private box audit home
- Desk or CRM dumps destined for public remotes

Safe to commit: this design doc, the gate script (no embedded terms), the example watchlist template with placeholders only, and the skill markdown that refers to watchlist terms generically.

## How bot, laptop, and CI cooperate

| Actor | Role |
|-------|------|
| Grok Bot (Layer A) | Daily org scan; scrub editable; write private inventory and report on the box |
| Laptop checkout | Local run can load `.client-name-watchlist.local` (gitignored) |
| Public CI, hardcoded scanner | `check-client-leaks.sh` always runs. No secret. Fails closed on its in-script literals |
| Public CI, watchlist gate | Inactive (warn, exit 0) unless `CLIENT_NAME_WATCHLIST_FILE` or `CLIENT_NAME_PATTERNS` is injected. Optional strict mode: `CLIENT_NAME_WATCHLIST_REQUIRED=1` |
| Soft locks (Layer C) | Templates and prompts stay generic so Layer A and Layer B see fewer new hits |

## Skill home

The repo-owned skill is `skills/client-name-public-github-audit/SKILL.md`.

`.claude/skills/` is the revcon copy-mode surface. `scripts/verify-copy-lockstep.sh` rejects a tracked file under `.claude/skills/` that is not in `.claude/.revcon-manifest.json`. This skill ships with the gate. It is not a revcon profile copy, so it does not live under `.claude/skills/`.

## Pointers

| Item | Path |
|------|------|
| Design (this file) | `docs/client-name-public-github.md` |
| Watchlist gate | `scripts/check-no-client-names.sh` |
| Watchlist gate CI (inactive without a secret) | `.github/workflows/check-no-client-names.yml` |
| Hardcoded scanner (stays) | `scripts/check-client-leaks.sh` |
| Hardcoded scanner CI | `.github/workflows/check-client-leaks.yml` |
| Path / private-leak companion | `scripts/check-no-private-leaks.sh` |
| Example watchlist | `templates/client-name-watchlist.example` |
| Skill | `skills/client-name-public-github-audit/SKILL.md` |
| Private watchlist (box) | `/workspace/client-name-github-audit/WATCHLIST.md` |
| Private inventory (box) | `/workspace/client-name-github-audit/INVENTORY.md` |

`.client-name-watchlist.local` must remain gitignored.
