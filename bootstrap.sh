#!/usr/bin/env bash
# bootstrap.sh — cross-platform RevKit bootstrap (macOS + Linux + WSL2).
#
# Replaces bootstrap-wsl.sh as the universal entry point. Detect-then-dispatch:
# everything that is platform-agnostic runs unconditionally; WSL-only steps are
# gated by revkit_is_wsl; macOS-specific paths are chosen by revkit_is_macos.
#
# Usage:
#   bash bootstrap.sh           # install
#   bash bootstrap.sh --dry-run # preview steps, make no changes

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load OS detection + capability predicates (sets REVKIT_OS; exports predicates).
. "$SCRIPT_DIR/lib/platform.sh"

echo ""
echo "=== RevKit Bootstrap ==="
echo "Source:   $SCRIPT_DIR"
echo "Platform: $REVKIT_OS"
[ "$DRY_RUN" -eq 1 ] && echo "Mode:     dry-run (no changes)"
echo ""

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Resolve platform-appropriate directories
# ---------------------------------------------------------------------------

# helpers dir: user-owned on macOS (no sudo), system-wide on Linux/WSL.
if revkit_is_macos; then
  HELPERS_DIR="$HOME/.local/bin"
else
  HELPERS_DIR="/usr/local/bin"
fi

# RC files: hook into every present rc file + the platform-primary one.
_rc_files=()
[ -f "$HOME/.bashrc" ] && _rc_files+=("$HOME/.bashrc")
[ -f "$HOME/.zshrc"  ] && _rc_files+=("$HOME/.zshrc")
# Ensure at least one file exists to receive the hook.
if [ ${#_rc_files[@]} -eq 0 ]; then
  if revkit_is_macos; then
    _rc_files+=("$HOME/.zshrc")
  else
    _rc_files+=("$HOME/.bashrc")
  fi
fi

# ---------------------------------------------------------------------------
# Step 1: Install helper scripts
# ---------------------------------------------------------------------------
echo "[1] Installing helper scripts to $HELPERS_DIR..."
if [ "$DRY_RUN" -eq 0 ] && ! revkit_is_macos; then
  sudo mkdir -p "$HELPERS_DIR"
elif [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$HELPERS_DIR"
fi

_installed=0
for script in "$SCRIPT_DIR/shell/bin/"*.sh; do
  [ -f "$script" ] || continue
  name="$(basename "$script")"
  # Skip WSL-only helpers on non-WSL platforms.
  case "$name" in
    mount-sandbox-drive.sh | sandbox-services.sh | sandbox-validate.sh | wsl-status.sh)
      if ! revkit_is_wsl; then
        printf '  [skip-wsl] %s\n' "$name"
        continue
      fi
      ;;
  esac
  if revkit_is_macos; then
    run cp "$script" "$HELPERS_DIR/$name"
    run chmod +x "$HELPERS_DIR/$name"
  else
    # Positional-arg form: $script reaches sed as "$1", never re-parsed by a
    # second shell (an injection-safe replacement for `bash -c "... $script ..."`).
    run sh -c 'sed "s/\r$//" "$1" | sudo tee "$2" >/dev/null' _ "$script" "$HELPERS_DIR/$name"
    run sudo chmod +x "$HELPERS_DIR/$name"
  fi
  printf '  Installed: %s/%s\n' "$HELPERS_DIR" "$name"
  _installed=$((_installed + 1))
done
printf '  %d helper(s) installed.\n' "$_installed"

# Shared shell libs (rfg worktree-env, mcp-env, …) next to helpers so installed
# rfg.sh can source them without requiring a revkit git checkout on PATH.
_lib_installed=0
_lib_dest="$(dirname "$HELPERS_DIR")/lib/revkit"
if [ "$DRY_RUN" -eq 0 ]; then
  if revkit_is_macos; then
    mkdir -p "$_lib_dest"
  else
    sudo mkdir -p "$_lib_dest"
  fi
fi
for lib in "$SCRIPT_DIR/shell/lib/"*.sh; do
  [ -f "$lib" ] || continue
  name="$(basename "$lib")"
  if revkit_is_macos; then
    run cp "$lib" "$_lib_dest/$name"
    run chmod 644 "$_lib_dest/$name"
  else
    run sh -c 'sed "s/\r$//" "$1" | sudo tee "$2" >/dev/null' _ "$lib" "$_lib_dest/$name"
    run sudo chmod 644 "$_lib_dest/$name"
  fi
  printf '  Installed lib: %s/%s\n' "$_lib_dest" "$name"
  _lib_installed=$((_lib_installed + 1))
done
printf '  %d shell lib(s) installed.\n' "$_lib_installed"

# ---------------------------------------------------------------------------
# Step 2: Sudoers — WSL only (passwordless mount for sandbox drive)
# ---------------------------------------------------------------------------
if revkit_is_wsl; then
  echo "[2] Configuring sudoers for passwordless mount..."
  SUDOERS_FILE="/etc/sudoers.d/wsl-revealui"
  CURRENT_USER="$(whoami)"
  if [ "$DRY_RUN" -eq 0 ]; then
    sudo tee "$SUDOERS_FILE" > /dev/null << EOF
# RevKit — passwordless mount (pinned to --mount-only; --init requires interactive sudo).
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
  else
    printf '  [dry-run] would write %s\n' "$SUDOERS_FILE"
  fi
else
  echo "[2] Sudoers — skipped (not WSL)"
fi

# ---------------------------------------------------------------------------
# Step 3: RC hook (bash + zsh)
# ---------------------------------------------------------------------------
echo "[3] Adding RevKit hook to rc file(s)..."
MARKER="# --- RevealUI environment mode ---"
END_MARKER="# --- end RevealUI ---"

for rcfile in "${_rc_files[@]}"; do
  # One-time pristine backup before any in-place rewrite. Guarded so re-runs
  # never clobber the original snapshot with already-modified content.
  if [ "$DRY_RUN" -eq 0 ] && [ -f "$rcfile" ] && [ ! -f "$rcfile.revkit.bak" ]; then
    cp "$rcfile" "$rcfile.revkit.bak"
  fi

  # Self-healing: remove any stale RevKit block before re-adding. Strip only
  # when BOTH markers are present — a lone OPEN marker (truncated/hand-edited
  # rc) would otherwise make awk drop everything to EOF.
  if grep -qF "$MARKER" "$rcfile" 2>/dev/null && grep -qF "$END_MARKER" "$rcfile" 2>/dev/null; then
    if [ "$DRY_RUN" -eq 0 ]; then
      # Temp beside the target so the final mv is an atomic same-fs rename.
      _tmp="$(mktemp "${rcfile}.revkit.XXXXXX")"
      # END guard: if the OPEN block never closed, drop stays set -> exit 3 ->
      # leave the original untouched rather than truncate it.
      if awk -v s="$MARKER" -v e="$END_MARKER" '
        $0 == s { drop = 1 }
        drop != 1 { print }
        $0 == e { drop = 0 }
        END { if (drop) exit 3 }
      ' "$rcfile" > "$_tmp"; then
        mv "$_tmp" "$rcfile"
        printf '  Removed stale hook from %s (reinstalling)\n' "$rcfile"
      else
        rm -f "$_tmp"
        printf '  WARNING: %s has an unterminated RevKit block; left untouched\n' "$rcfile" >&2
      fi
    else
      printf '  Removed stale hook from %s (reinstalling)\n' "$rcfile"
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    # Atomic append: assemble (existing + new block) in a sibling temp, then
    # rename into place so the rc file is never left half-written.
    _tmp="$(mktemp "${rcfile}.revkit.XXXXXX")"
    [ -f "$rcfile" ] && cat "$rcfile" > "$_tmp"
    cat >> "$_tmp" << HOOKEOF

# --- RevealUI environment mode ---
# REVEALUI_ROOT pinned at bootstrap — update here if you move the revkit repo.
export REVEALUI_ROOT="$SCRIPT_DIR"
# Guard: detect and print once per terminal session; subshells inherit REVEALUI_MODE.
if [ -z "\${REVEALUI_MODE:-}" ]; then
  if [ -f "\${REVEALUI_ROOT}/shell/shellrc.d/00-base.sh" ]; then
    export REVEALUI_MODE="managed"
    for _f in "\$REVEALUI_ROOT"/shell/shellrc.d/*.sh; do
      [ -r "\$_f" ] && . "\$_f"
    done
    printf '\033[1;36m● RevKit: managed\033[0m (%s)\n' "\$REVEALUI_ROOT"
  else
    export REVEALUI_MODE="bare"
    printf '\033[0;37m● RevKit: bare\033[0m\n'
  fi
  unset _f
fi
# --- end RevealUI ---
HOOKEOF
    mv "$_tmp" "$rcfile"
  else
    printf '  [dry-run] would append hook to %s\n' "$rcfile"
  fi
  printf '  Hook installed: %s\n' "$rcfile"
done

# ---------------------------------------------------------------------------
# Step 4: Git + SSH configs
# ---------------------------------------------------------------------------
echo "[4] Linking git and SSH configs..."
CONFIGS_DIR="$SCRIPT_DIR/shell/config"
LOCAL_CFG="$HOME/.config/revkit"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$LOCAL_CFG"
  if [ ! -f "$LOCAL_CFG/identity.gitconfig" ]; then
    _gn="$(git config --global user.name 2>/dev/null || true)"
    _ge="$(git config --global user.email 2>/dev/null || true)"
    {
      echo "# RevKit per-user git identity — machine-local, never committed."
      echo "[user]"
      printf '\tname = %s\n' "$_gn"
      printf '\temail = %s\n' "$_ge"
    } > "$LOCAL_CFG/identity.gitconfig"
    if [ -n "$_gn" ] && [ -n "$_ge" ]; then
      echo "  Seeded $LOCAL_CFG/identity.gitconfig from existing git identity"
    else
      echo "  Created $LOCAL_CFG/identity.gitconfig — set your git name + email there"
    fi
  else
    echo "  $LOCAL_CFG/identity.gitconfig already exists"
  fi

  if [ ! -f "$LOCAL_CFG/ssh.local" ]; then
    {
      echo "# RevKit per-user SSH overrides — machine-local, never committed."
      echo "# Add Host blocks here; the tracked ssh-config includes this file."
    } > "$LOCAL_CFG/ssh.local"
    echo "  Created $LOCAL_CFG/ssh.local"
  fi

  if [ -f "$CONFIGS_DIR/gitconfig" ]; then
    git config --global include.path "$CONFIGS_DIR/gitconfig"
    echo "  Git config: include.path → $CONFIGS_DIR/gitconfig"
  fi

  if [ -f "$CONFIGS_DIR/ssh-config" ]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    if ! grep -qF "Include $CONFIGS_DIR/ssh-config" ~/.ssh/config 2>/dev/null; then
      if [ -f ~/.ssh/config ]; then
        _tmp="$(mktemp)"
        printf 'Include %s\n\n' "$CONFIGS_DIR/ssh-config" > "$_tmp"
        cat ~/.ssh/config >> "$_tmp"
        mv "$_tmp" ~/.ssh/config
      else
        printf 'Include %s\n' "$CONFIGS_DIR/ssh-config" > ~/.ssh/config
      fi
      chmod 600 ~/.ssh/config
      echo "  SSH config: Include directive added"
    else
      echo "  SSH config: Include already present"
    fi
  fi
else
  printf '  [dry-run] would seed %s/{identity.gitconfig,ssh.local}\n' "$LOCAL_CFG"
  printf '  [dry-run] would set git include.path + SSH Include\n'
fi

# ---------------------------------------------------------------------------
# Step 5: WSL boot optimization — WSL only
# ---------------------------------------------------------------------------
if revkit_is_wsl; then
  echo "[5] Running WSL boot optimization..."
  BOOT_SCRIPT="$SCRIPT_DIR/shell/setup-wsl-boot.sh"
  if [ -f "$BOOT_SCRIPT" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      sudo bash "$BOOT_SCRIPT"
    else
      printf '  [dry-run] would run %s\n' "$BOOT_SCRIPT"
    fi
  else
    printf '  WARNING: %s not found, skipping\n' "$BOOT_SCRIPT" >&2
  fi
else
  echo "[5] WSL boot optimization — skipped (not WSL)"
fi

# ---------------------------------------------------------------------------
# Step 6: Sandbox directory init — WSL only
# ---------------------------------------------------------------------------
if revkit_is_wsl; then
  if mountpoint -q /mnt/sandbox 2>/dev/null; then
    echo "[6] Initializing Sandbox directories..."
    for d in databases/postgres databases/redis databases/supabase models cache; do
      run mkdir -p "/mnt/sandbox/$d"
    done
    echo "  Sandbox directories initialized"
  else
    echo "[6] Sandbox drive not mounted, skipping directory init"
  fi
else
  echo "[6] Sandbox directories — skipped (not WSL)"
fi

# ---------------------------------------------------------------------------
# Step 7: Claude global config (~/.claude) via the claude-config repo
# ---------------------------------------------------------------------------
# Durable replacement for the RETIRED symlink-into-worktree mechanism: ~/.claude
# is a real-file git clone of claude-config (layer L1); reusable skills come from
# the revskills plugin (layer L2, declared in claude-config's settings.json).
# NEVER symlink ~/.claude entries into a revfleet worktree — that outage is what
# this step exists to prevent.
echo "[7] Wiring Claude global config (~/.claude) from claude-config..."
CC_REMOTE="git@github.com-revealui:RevealUIStudio/claude-config.git"
CC_DIR="$HOME/.claude"

if ! command -v git >/dev/null 2>&1; then
  echo "  WARNING: git not in PATH — skipping claude-config" >&2
elif [ -d "$CC_DIR/.git" ]; then
  _cc_origin="$(git -C "$CC_DIR" remote get-url origin 2>/dev/null || true)"
  case "$_cc_origin" in
    *claude-config*)
      # Already our repo — fast-forward only. Never resets/clobbers: machine-local
      # runtime state (projects/, sessions/, history.jsonl, settings.local.json)
      # is untracked + gitignored and is left exactly as-is.
      if [ "$DRY_RUN" -eq 0 ]; then
        git -C "$CC_DIR" fetch --quiet origin main || true
        if git -C "$CC_DIR" merge --ff-only origin/main >/dev/null 2>&1; then
          echo "  claude-config: fast-forwarded ~/.claude to origin/main"
        else
          echo "  claude-config: local main diverged from origin/main; left as-is (reconcile manually)"
        fi
      else
        printf '  [dry-run] would fetch + ff-only merge %s\n' "$CC_REMOTE"
      fi
      ;;
    *)
      printf '  WARNING: %s is a git repo with a different origin (%s); left untouched\n' \
        "$CC_DIR" "${_cc_origin:-none}" >&2
      ;;
  esac
else
  # Fresh machine: initialize ~/.claude as a claude-config clone IN PLACE so any
  # pre-existing runtime state is preserved. checkout WITHOUT -f aborts rather
  # than overwrite an existing real config file — non-clobbering by construction.
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$CC_DIR"
    git -C "$CC_DIR" init --quiet
    git -C "$CC_DIR" remote add origin "$CC_REMOTE" 2>/dev/null || \
      git -C "$CC_DIR" remote set-url origin "$CC_REMOTE"
    if git -C "$CC_DIR" fetch --quiet origin main && \
       git -C "$CC_DIR" checkout -B main origin/main >/dev/null 2>&1; then
      git -C "$CC_DIR" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
      echo "  claude-config: initialized ~/.claude from origin/main (real files, no symlinks)"
    else
      echo "  WARNING: could not populate ~/.claude from claude-config" >&2
      echo "           (pre-existing config files or fetch failed); left untouched — reconcile manually" >&2
    fi
  else
    printf '  [dry-run] would git init %s + fetch/checkout %s\n' "$CC_DIR" "$CC_REMOTE"
  fi
fi

# Assertion: the retired anti-pattern must never return. Fail loudly if any
# ~/.claude entry is a symlink pointing into a revfleet worktree.
if [ -d "$CC_DIR" ]; then
  _cc_bad="$(find "$CC_DIR" -maxdepth 2 -type l -lname '*revfleet*' 2>/dev/null || true)"
  if [ -n "$_cc_bad" ]; then
    printf '  ERROR: symlink-into-worktree detected under ~/.claude (retired mechanism):\n' >&2
    printf '%s\n' "$_cc_bad" >&2
    exit 1
  fi
fi

# revskills skills plugin (L2): declare the marketplace so `claude` can resolve
# the enabledPlugins entry already present in claude-config's settings.json.
# Idempotent — only adds when absent.
if command -v claude >/dev/null 2>&1; then
  if claude plugin marketplace list 2>/dev/null | grep -q "revskills"; then
    echo "  revskills marketplace already present"
  elif [ "$DRY_RUN" -eq 0 ]; then
    if claude plugin marketplace add RevealUIStudio/revskills >/dev/null 2>&1; then
      echo "  revskills marketplace added"
    else
      echo "  WARNING: could not add revskills marketplace (add manually if needed)" >&2
    fi
  else
    printf '  [dry-run] would run: claude plugin marketplace add RevealUIStudio/revskills\n'
  fi
else
  echo "  claude CLI not in PATH — skipping revskills marketplace add (settings.json still declares it)"
fi

# ---------------------------------------------------------------------------
# Step 8: Claude Code M-4 scanner hook
# ---------------------------------------------------------------------------
echo "[8] Deploying Claude Code M-4 scanner hook..."
CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
M4_SRC="$SCRIPT_DIR/shell/bin/m4-sudoers-fs-scanner.js"
M4_DEST="$CLAUDE_HOOKS_DIR/m4-sudoers-fs-scanner.js"

if [ ! -f "$M4_SRC" ]; then
  printf '  WARNING: %s not found — M-4 scanner not deployed\n' "$M4_SRC" >&2
elif ! command -v node >/dev/null 2>&1; then
  echo "  WARNING: node not in PATH — skipping M-4 scanner deploy" >&2
else
  if ! node --check "$M4_SRC" >/dev/null 2>&1; then
    printf '  ERROR: %s failed node --check; refusing to deploy\n' "$M4_SRC" >&2
    exit 1
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$CLAUDE_HOOKS_DIR"
    if [ -f "$M4_DEST" ] && cmp -s "$M4_SRC" "$M4_DEST"; then
      echo "  $M4_DEST already up to date"
    else
      sed 's/\r$//' "$M4_SRC" > "$M4_DEST"
      chmod 0644 "$M4_DEST"
      printf '  Deployed: %s\n' "$M4_DEST"
    fi
  else
    printf '  [dry-run] would deploy to %s\n' "$M4_DEST"
  fi
  echo "  Note: wire M-4 into ~/.claude/hooks/session-start.js (one-time edit)"
fi

# ---------------------------------------------------------------------------
# Step 9: RevFleet Claude rules via revcon/link.sh
# ---------------------------------------------------------------------------
echo "[9] Wiring RevFleet Claude rules via revcon/link.sh..."
REVCON_LINK_SH="$HOME/revfleet/revcon/link.sh"
REVFLEET_ROOT="$HOME/revfleet"

if [ ! -f "$REVCON_LINK_SH" ]; then
  echo "  WARNING: $REVCON_LINK_SH not found — skipping (clone RevealUIStudio/revcon first)" >&2
else
  # Fleet repos to wire (operator-editable). These are this org's public repos;
  # edit the list for your own fleet. Cancelled/retired products are omitted.
  # Entry format: repo:profiles_csv[:mode] — mode is symlink (default) or
  # copy. Copy mode materializes tracked files with a .revcon-manifest.json
  # (revealui gates them via validate:rules-lockstep).
  FLEET_TARGETS=(
    "revealui:revfleet,revealui:copy"
    "revdev:revfleet:copy"
    "revvault:revfleet:copy"
    "revcon:revfleet:copy"
    "revforge:revfleet:copy"
    "revskills:revfleet:copy"
    "revkit:revfleet:copy"
  )
  for entry in "${FLEET_TARGETS[@]}"; do
    repo="${entry%%:*}"
    rest="${entry#*:}"
    profiles_csv="${rest%%:*}"
    mode="symlink"
    case "$rest" in
      *:*) mode="${rest#*:}" ;;
    esac
    target_dir="$REVFLEET_ROOT/$repo"
    if [ ! -d "$target_dir" ]; then
      printf '  [skip] %s not found at %s\n' "$repo" "$target_dir"
      continue
    fi
    profile_args=()
    IFS=',' read -ra _profiles <<< "$profiles_csv"
    for p in "${_profiles[@]}"; do
      profile_args+=("--profile" "$p")
    done
    printf '  [%s] profiles: %s (mode: %s)\n' "$repo" "$profiles_csv" "$mode"
    if [ "$DRY_RUN" -eq 0 ]; then
      bash "$REVCON_LINK_SH" --target "$target_dir" --editor claude --mode "$mode" "${profile_args[@]}" 2>&1 | sed 's/^/    /'
    else
      printf '  [dry-run] would run revcon/link.sh for %s\n' "$repo"
    fi
  done
  echo "  Done."
fi

# ---------------------------------------------------------------------------
# Step 10: Fleet-wide pre-push hook (M-11)
# ---------------------------------------------------------------------------
echo "[10] Wiring fleet-wide pre-push hook (M-11)..."
HOOKS_SRC_DIR="$SCRIPT_DIR/git-hooks"
PRE_PUSH_HOOK="$HOOKS_SRC_DIR/pre-push"
# Deploy hooks to a stable, user-owned path OUTSIDE the repo. Pointing
# core.hooksPath at the in-repo copy would run a CRLF-corrupted hook whenever
# the tree was checked out with autocrlf=true; deploying an LF-normalized copy
# here keeps M-11 working regardless of the clone's line-ending settings.
HOOKS_DIR="$HOME/.config/revkit/git-hooks"

if [ ! -f "$PRE_PUSH_HOOK" ]; then
  printf '  WARNING: %s not found — skipping M-11\n' "$PRE_PUSH_HOOK" >&2
elif ! bash -n "$PRE_PUSH_HOOK" >/dev/null 2>&1; then
  printf '  ERROR: %s failed bash -n; refusing to wire M-11\n' "$PRE_PUSH_HOOK" >&2
  exit 1
else
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$HOOKS_DIR"
    sed 's/\r$//' "$PRE_PUSH_HOOK" > "$HOOKS_DIR/pre-push"
    chmod +x "$HOOKS_DIR/pre-push"
    EXISTING="$(git config --global --get core.hooksPath 2>/dev/null || true)"
    if [ "$EXISTING" = "$HOOKS_DIR" ]; then
      echo "  global core.hooksPath already set (no-op)"
    elif [ -z "$EXISTING" ] || [ "$EXISTING" = "$HOOKS_SRC_DIR" ]; then
      # Fresh install, or migrating off the legacy in-repo hooks path.
      git config --global core.hooksPath "$HOOKS_DIR"
      printf '  Set: global core.hooksPath = %s\n' "$HOOKS_DIR"
    else
      printf '  ERROR: global core.hooksPath already points elsewhere:\n' >&2
      printf '    current: %s\n' "$EXISTING" >&2
      printf '    revkit:  %s\n' "$HOOKS_DIR" >&2
      printf '  Resolve: git config --global --unset core.hooksPath\n' >&2
      exit 1
    fi
    echo "  M-11 active: pre-push rejects direct/force/unsigned pushes to main + test"
  else
    printf '  [dry-run] would deploy LF-normalized pre-push to %s and set core.hooksPath\n' "$HOOKS_DIR"
  fi
fi

echo ""
echo "=== RevKit Bootstrap Complete ($REVKIT_OS) ==="
echo ""
echo "Restart your shell or:"
if revkit_is_macos; then
  echo "  source ~/.zshrc"
else
  echo "  source ~/.bashrc"
fi
echo ""
