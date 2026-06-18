#!/bin/bash
# RevealUI WSL Bootstrap
# Run ONCE inside an interactive WSL session:
#   bash /mnt/c/Users/<your-windows-user>/.revealui/bootstrap-wsl.sh
#   (or from portable SSD: bash /mnt/<drive>/.revealui/bootstrap-wsl.sh)
#   (or set REVEALUI_ROOT explicitly: REVEALUI_ROOT=/path/to/.revealui bash .../bootstrap-wsl.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "=== RevealUI WSL Bootstrap ==="
echo "Source: $SCRIPT_DIR"
echo ""

# --- Step 1: Install helper scripts to /usr/local/bin ---
echo "[1/9] Installing helper scripts to /usr/local/bin..."
for script in "$SCRIPT_DIR/shell/bin/"*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script")
    # Strip Windows line endings and install
    sed 's/\r$//' "$script" | sudo tee "/usr/local/bin/$name" > /dev/null
    sudo chmod +x "/usr/local/bin/$name"
    echo "  Installed: /usr/local/bin/$name"
done

# --- Step 2: Set up sudoers for passwordless mount ---
# The NOPASSWD rule pins to the exact `--mount-only` argument so any future
# expansion of mount-sandbox-drive.sh's argument surface (new flags, alternate
# mount points) is automatically rejected by sudoers until this rule is
# updated. The `--init` mode (one-time marker setup) intentionally requires
# interactive sudo and is NOT covered here.
#
# To add a new arg to mount-sandbox-drive.sh, update the NOPASSWD rule below
# AND every caller to pass the new arg list verbatim. See the script's
# own header comment for context (GAP-119, 2026-04-24).
echo "[2/9] Configuring sudoers for passwordless mount..."
SUDOERS_FILE="/etc/sudoers.d/wsl-revealui"
CURRENT_USER=$(whoami)
sudo tee "$SUDOERS_FILE" > /dev/null << EOF
# RevealUI - passwordless mount operations (restricted to mount helper +
# pinned to --mount-only argument; --init still requires interactive sudo).
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/local/bin/mount-sandbox-drive.sh --mount-only
EOF
sudo chmod 0440 "$SUDOERS_FILE"
if sudo visudo -cf "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "  Sudoers validated (NOPASSWD pinned to --mount-only)"
else
    echo "  ERROR: Sudoers syntax error, removing" >&2
    sudo rm "$SUDOERS_FILE"
    exit 1
fi

# --- Step 3: Add hook to .bashrc ---
echo "[3/9] Adding RevealUI hook to ~/.bashrc..."
MARKER="# --- RevealUI environment mode ---"
END_MARKER="# --- end RevealUI ---"
# Self-healing: strip any existing RevealUI block (legacy wsl/ path or
# current shell/ path) before appending, so re-running bootstrap after an
# upgrade migrates the in-home hook in place. This is the documented upgrade
# path for installs predating the wsl/ -> shell/ rename.
if grep -qF "$MARKER" ~/.bashrc 2>/dev/null; then
    _bashrc_tmp="$(mktemp)"
    awk -v s="$MARKER" -v e="$END_MARKER" '
        $0 == s { drop = 1 }
        drop != 1 { print }
        $0 == e { drop = 0 }
    ' ~/.bashrc > "$_bashrc_tmp" && mv "$_bashrc_tmp" ~/.bashrc
    echo "  Removed stale RevealUI hook (reinstalling current version)"
fi
cat >> ~/.bashrc << 'HOOK'

# --- RevealUI environment mode ---
# Guard: only detect and print once per terminal session.
# REVEALUI_MODE is exported, so subshells (e.g. direnv) inherit it
# and skip the detection block entirely.
if [ -z "$REVEALUI_MODE" ]; then
    _revealui_root=""
    # Explicit override wins
    if [ -n "${REVEALUI_ROOT:-}" ] && [ -f "${REVEALUI_ROOT}/shell/shellrc.d/00-base.sh" ]; then
        _revealui_root="$REVEALUI_ROOT"
    else
        # Primary: any Windows user's .revealui under /mnt/c/Users/* (works for any account name)
        for _candidate in /mnt/c/Users/*/.revealui; do
            if [ -f "$_candidate/shell/shellrc.d/00-base.sh" ]; then
                _revealui_root="$_candidate"
                break
            fi
        done
        # Fallback: scan known portable SSD locations
        if [ -z "$_revealui_root" ]; then
            for _candidate in /mnt/?/.revealui /mnt/?/professional/.revealui; do
                if [ -f "$_candidate/shell/shellrc.d/00-base.sh" ]; then
                    _revealui_root="$_candidate"
                    break
                fi
            done
        fi
    fi

    if [ -n "$_revealui_root" ]; then
        export REVEALUI_MODE="managed"
        export REVEALUI_ROOT="$_revealui_root"
        for _f in "$_revealui_root"/shell/shellrc.d/*.sh; do
            [ -r "$_f" ] && . "$_f"
        done
        echo -e "\033[1;36m● RevealUI: managed\033[0m ($_revealui_root)"
    else
        export REVEALUI_MODE="bare"
        unset REVEALUI_ROOT
        echo -e "\033[0;37m● RevealUI: bare\033[0m"
    fi
    unset _revealui_root _candidate _f
fi
# --- end RevealUI ---
HOOK
echo "  RevealUI hook installed in ~/.bashrc"

# --- Step 4: Link git and SSH configs ---
echo "[4/9] Linking git and SSH configs..."
CONFIGS_DIR="$SCRIPT_DIR/shell/config"

if [ -f "$CONFIGS_DIR/gitconfig" ]; then
    git config --global include.path "$CONFIGS_DIR/gitconfig"
    echo "  Git config: include.path set to $CONFIGS_DIR/gitconfig"
fi

if [ -f "$CONFIGS_DIR/ssh-config" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if ! grep -qF "Include $CONFIGS_DIR/ssh-config" ~/.ssh/config 2>/dev/null; then
        if [ -f ~/.ssh/config ]; then
            TMP=$(mktemp)
            echo "Include $CONFIGS_DIR/ssh-config" > "$TMP"
            echo "" >> "$TMP"
            cat ~/.ssh/config >> "$TMP"
            mv "$TMP" ~/.ssh/config
        else
            echo "Include $CONFIGS_DIR/ssh-config" > ~/.ssh/config
        fi
        chmod 600 ~/.ssh/config
        echo "  SSH config: Include directive added"
    else
        echo "  SSH config: Include already present"
    fi
fi

# --- Step 5: Run boot optimization ---
echo "[5/9] Running boot optimization..."
BOOT_SCRIPT="$SCRIPT_DIR/shell/setup-wsl-boot.sh"
if [ -f "$BOOT_SCRIPT" ]; then
    sudo bash "$BOOT_SCRIPT"
else
    echo "  WARNING: $BOOT_SCRIPT not found, skipping" >&2
fi

# --- Step 6: Initialize Sandbox directories ---
if mountpoint -q /mnt/sandbox 2>/dev/null; then
    echo "[6/9] Initializing Sandbox directories..."
    mkdir -p /mnt/sandbox/databases/postgres
    mkdir -p /mnt/sandbox/databases/redis
    mkdir -p /mnt/sandbox/databases/supabase
    mkdir -p /mnt/sandbox/models
    mkdir -p /mnt/sandbox/cache
    echo "  Sandbox directories initialized"
else
    echo "[6/9] Sandbox drive not mounted, skipping directory init"
fi

# --- Step 7: Deploy Claude Code hooks (M-4 scanner + future hooks) ---
# Spec: internal fleet-security-hardening lane § M-4 (meta-durability-fixes)
#
# Scope (intentionally narrow): only the M-4 sudoers + filesystem invariant
# scanner is deployed here. The other hooks under ~/.claude/hooks/
# (session-start.js, post-edit.js, etc.) are NOT touched — they have a
# separate lifecycle. Adopting hooks wholesale via revkit is its own
# initiative; M-4 carves out only what M-4 needs.
#
# Idempotent: copies are content-checked first; bashrc-style banner notes
# what happened.
echo "[7/9] Deploying Claude Code M-4 scanner hook..."
CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
M4_SRC="$SCRIPT_DIR/shell/bin/m4-sudoers-fs-scanner.js"
M4_DEST="$CLAUDE_HOOKS_DIR/m4-sudoers-fs-scanner.js"

if [ ! -f "$M4_SRC" ]; then
    echo "  WARNING: $M4_SRC not found — M-4 scanner not deployed" >&2
elif ! command -v node >/dev/null 2>&1; then
    echo "  WARNING: node not in PATH — skipping M-4 scanner syntax check + deploy" >&2
else
    # Validate before deploying — never copy a broken hook into the user's
    # Claude Code session-start chain.
    if ! node --check "$M4_SRC" >/dev/null 2>&1; then
        echo "  ERROR: $M4_SRC failed node --check; refusing to deploy" >&2
        exit 1
    fi
    mkdir -p "$CLAUDE_HOOKS_DIR"
    # cmp -s returns 0 if identical; only copy when content differs to
    # avoid touching mtime on every bootstrap re-run.
    if [ -f "$M4_DEST" ] && cmp -s "$M4_SRC" "$M4_DEST"; then
        echo "  $M4_DEST already up to date"
    else
        sed 's/\r$//' "$M4_SRC" > "$M4_DEST"
        chmod 0644 "$M4_DEST"
        echo "  Deployed: $M4_DEST"
    fi
    echo "  Note: M-4 invocation must be wired into ~/.claude/hooks/session-start.js"
    echo "        (one-time edit; see meta-durability-fixes.md §M-4 integration)"
fi

# --- Step 8: Wire RevFleet Claude rules per-repo via revcon/link.sh ---
# Architecture: revcon owns Claude content, revkit installs it. Each RevFleet
# repo gets the `revfleet` profile; revealui additionally gets the `revealui`
# profile (later overrides earlier on filename collision — supported by
# revcon/link.sh as of PR #38 — repeatable --profile flag).
#
# Scope: --editor claude only. Fleet-wide cursor/zed standardization
# (revcon/base/{cursor,zed}) is a separate decision and is NOT triggered
# from here. To expand later, drop the --editor flag on the link.sh call.
#
# Idempotent: link.sh dedupes via existing-symlink-target check; re-running
# bootstrap re-links the same paths and reports them as unchanged.
#
# Fail-loud: if link.sh errors (e.g. revfleet profile missing, or repeated
# --profile unsupported by an older link.sh), bootstrap halts. Update
# revcon to the required version (>= PR #37 + PR #38 merged) and re-run.
echo "[8/9] Wiring RevFleet Claude rules via revcon/link.sh..."
REVCON_LINK_SH="$HOME/revfleet/revcon/link.sh"
REVFLEET_ROOT="$HOME/revfleet"

if [ ! -f "$REVCON_LINK_SH" ]; then
    echo "  WARNING: $REVCON_LINK_SH not found — skipping Claude rules wiring" >&2
    echo "  (clone RevealUIStudio/revcon to ~/revfleet/revcon, then re-run)"
elif ! command -v bash >/dev/null 2>&1; then
    echo "  WARNING: bash not in PATH — skipping Claude rules wiring" >&2
else
    # Per-repo profile assignment. Format: "repo:profile1[,profile2,...]"
    # Sibling repos get revfleet only; revealui adds the monorepo overlay.
    FLEET_TARGETS=(
        "revealui:revfleet,revealui"
        "revdev:revfleet"
        "revvault:revfleet"
        "revcon:revfleet"
        "revealcoin:revfleet"
        "revforge:revfleet"
        "revskills:revfleet"
        "revkit:revfleet"
    )

    for entry in "${FLEET_TARGETS[@]}"; do
        repo="${entry%%:*}"
        profiles_csv="${entry#*:}"
        target_dir="$REVFLEET_ROOT/$repo"

        if [ ! -d "$target_dir" ]; then
            echo "  [skip] $repo not checked out at $target_dir"
            continue
        fi

        # Translate CSV → repeated --profile flags
        profile_args=()
        IFS=',' read -ra profile_list <<< "$profiles_csv"
        for p in "${profile_list[@]}"; do
            profile_args+=("--profile" "$p")
        done

        echo "  [$repo] profiles: $profiles_csv"
        bash "$REVCON_LINK_SH" --target "$target_dir" --editor claude "${profile_args[@]}" 2>&1 | sed 's/^/    /'
    done

    echo "  Done. RevFleet Claude rules wired per-repo."
fi

# --- Step 9: Wire fleet-wide pre-push hook (M-11) ---
# Spec: internal fleet-security-hardening lane, meta-durability-fixes §M-11
#
# Class killed: absent server-side branch protection on private repos (T0-15;
# GitHub Free rejects branch-protection API on private repos and owner has
# rejected the Team upgrade). The next-best durable enforcement is a uniformly-
# installed local pre-push hook deployed via global core.hooksPath, so every
# clone in the dev environment inherits the hook without per-clone setup.
#
# Source-of-truth: $SCRIPT_DIR/git-hooks/ — updates land on `git pull` of revkit
# without re-running bootstrap. Re-running bootstrap is idempotent.
#
# Conflict handling (per design): fail-loudly when the user already has a
# different global core.hooksPath. Silent overwrite would clobber another
# tool's setup; silent skip would silently disable M-11. The user decides.
echo "[9/9] Wiring fleet-wide pre-push hook (M-11)..."
HOOKS_DIR="$SCRIPT_DIR/git-hooks"
PRE_PUSH_HOOK="$SCRIPT_DIR/git-hooks/pre-push"

if [ ! -d "$HOOKS_DIR" ] || [ ! -f "$PRE_PUSH_HOOK" ]; then
    echo "  WARNING: $HOOKS_DIR/pre-push not found — skipping M-11 wiring" >&2
elif ! command -v git >/dev/null 2>&1; then
    echo "  WARNING: git not in PATH — skipping M-11 wiring" >&2
else
    # Validate the hook is syntactically parseable before pointing core.hooksPath at it.
    if ! bash -n "$PRE_PUSH_HOOK" >/dev/null 2>&1; then
        echo "  ERROR: $PRE_PUSH_HOOK failed bash -n; refusing to wire M-11" >&2
        exit 1
    fi
    # Ensure the executable bit is set. UNC writes from Windows land 0644 on
    # WSL ext4; the bit is reset on every checkout from a UNC-side commit.
    chmod +x "$PRE_PUSH_HOOK"

    # Read current global hooksPath. `git config --global --get` exits 1 when
    # the key is unset — capture that without tripping `set -e`.
    EXISTING_HOOKS_PATH="$(git config --global --get core.hooksPath 2>/dev/null || true)"

    if [ -z "$EXISTING_HOOKS_PATH" ]; then
        git config --global core.hooksPath "$HOOKS_DIR"
        echo "  Set: global core.hooksPath = $HOOKS_DIR"
    elif [ "$EXISTING_HOOKS_PATH" = "$HOOKS_DIR" ]; then
        echo "  global core.hooksPath already = $HOOKS_DIR (no-op)"
    else
        # Fail loudly. Do not silently overwrite (would clobber another tool)
        # or silently skip (would disable M-11). Owner decides.
        echo "  ERROR: global core.hooksPath is already set to a DIFFERENT path:" >&2
        echo "    current: $EXISTING_HOOKS_PATH" >&2
        echo "    revkit:  $HOOKS_DIR" >&2
        echo "  Resolve manually, then re-run bootstrap:" >&2
        echo "    git config --global --unset core.hooksPath" >&2
        echo "  Then: bash $0" >&2
        exit 1
    fi
    echo "  M-11 active: pre-push will reject direct/force/unsigned pushes to main + test"
    echo "  Per-repo escape hatch: git config revealui.hooks.no-protection true"
fi

echo ""
echo "=== WSL Bootstrap Complete ==="
echo ""
echo "Restart your shell or run: source ~/.bashrc"
echo "Then restart WSL from Windows: wsl --shutdown"
echo ""
