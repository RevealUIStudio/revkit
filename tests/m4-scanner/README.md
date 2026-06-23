# M-4 scanner — smoke tests

Smoke tests for `revkit/shell/bin/m4-sudoers-fs-scanner.js`.

## Spec

Internal fleet-security-hardening lane § M-4 (meta-durability-fixes). Private spec — link omitted to keep revkit publishable.

## Run

```bash
bash revkit/tests/m4-scanner/test-m4-scanner.sh
bash revkit/tests/m4-scanner/test-m4-scanner.sh --verbose
```

## Approach

Each test sets up an isolated fixture tree in `$(mktemp -d)` and invokes the scanner with these env vars pointing at the fixtures:

- `M4_SUDOERS_DIR_OVERRIDE` — pretend `/etc/sudoers.d` is this dir
- `M4_FS_OVERRIDE_HOME` — pretend `$HOME` is this dir (for `~/.age-identity`, `~/.ssh`, `~/.revealui`)
- `M4_FS_OVERRIDE_SUDOLOG` — path to use instead of `/var/log/sudo.log`

The system paths are never touched. Tests assert on:

- Exit code (0 for clean, 2 for violation)
- stderr contains the expected violation marker (via `grep -qF`, literal-string match — no regex)

## Cleanup

`trap 'rm -rf "$FIXTURES_ROOT"' EXIT` removes the fixture tree on exit, including failure paths.

## Test coverage matrix

| # | Class | What it tests |
|---|---|---|
| 1 | baseline | Clean fixture → exit 0, no findings |
| 2 | sudoers | `NOPASSWD: ALL` flagged |
| 3 | sudoers | `NOPASSWD: /usr/bin/mount` flagged |
| 4 | sudoers | Glob char in arg list flagged |
| 5 | sudoers | `/usr/local/bin/<script>` without pinned arg flagged |
| 6 | sudoers | NOPASSWD entry without `# justification:` flagged |
| 7 | sudoers | `00-defaults` missing required keyword (`log_subcmds`) flagged |
| 8 | sudoers | `00-defaults` file absent flagged |
| 9 | filesystem | `~/.age-identity/keys.txt` mode 744 flagged |
| 10 | filesystem | `~/.age-identity` dir mode 755 flagged |
| 11 | filesystem | `~/.ssh/id_ed25519` mode 644 flagged |
| 12 | filesystem | `~/.ssh/id_ed25519.pub` ignored at any mode |
| 13 | sudoers | Correctly-pinned NOPASSWD + justification → exit 0 |
| 14 | filesystem | `~/.revealui/passage-store` mode 750 flagged (> 700 maxMode) |
| 15 | mixed | Multiple violations all reported |
| 16 | filesystem | `/var/log/sudo.log` mode 644 flagged |
