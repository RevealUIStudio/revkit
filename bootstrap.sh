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
  # Self-healing: remove any stale RevKit block before re-adding.
  if grep -qF "$MARKER" "$rcfile" 2>/dev/null; then
    if [ "$DRY_RUN" -eq 0 ]; then
      _tmp="$(mktemp)"
      awk -v s="$MARKER" -v e="$END_MARKER" '
        $0 == s { drop = 1 }
        drop != 1 { print }
        $0 == e { drop = 0 }
      ' "$rcfile" > "$_tmp" && mv "$_tmp" "$rcfile"
    fi
    printf '  Removed stale hook from %s (reinstalling)\n' "$rcfile"
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    cat >> "$rcfile" << HOOKEOF

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
# Step 7: Claude Code M-4 scanner hook
# ---------------------------------------------------------------------------
echo "[7] Deploying Claude Code M-4 scanner hook..."
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
# Step 8: RevFleet Claude rules via revcon/link.sh
# ---------------------------------------------------------------------------
echo "[8] Wiring RevFleet Claude rules via revcon/link.sh..."
REVCON_LINK_SH="$HOME/revfleet/revcon/link.sh"
REVFLEET_ROOT="$HOME/revfleet"

if [ ! -f "$REVCON_LINK_SH" ]; then
  echo "  WARNING: $REVCON_LINK_SH not found — skipping (clone RevealUIStudio/revcon first)" >&2
else
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
      printf '  [skip] %s not found at %s\n' "$repo" "$target_dir"
      continue
    fi
    profile_args=()
    IFS=',' read -ra _profiles <<< "$profiles_csv"
    for p in "${_profiles[@]}"; do
      profile_args+=("--profile" "$p")
    done
    printf '  [%s] profiles: %s\n' "$repo" "$profiles_csv"
    if [ "$DRY_RUN" -eq 0 ]; then
      bash "$REVCON_LINK_SH" --target "$target_dir" --editor claude "${profile_args[@]}" 2>&1 | sed 's/^/    /'
    else
      printf '  [dry-run] would run revcon/link.sh for %s\n' "$repo"
    fi
  done
  echo "  Done."
fi

# ---------------------------------------------------------------------------
# Step 9: Fleet-wide pre-push hook (M-11)
# ---------------------------------------------------------------------------
echo "[9] Wiring fleet-wide pre-push hook (M-11)..."
HOOKS_DIR="$SCRIPT_DIR/git-hooks"
PRE_PUSH_HOOK="$HOOKS_DIR/pre-push"

if [ ! -f "$PRE_PUSH_HOOK" ]; then
  printf '  WARNING: %s not found — skipping M-11\n' "$PRE_PUSH_HOOK" >&2
elif ! bash -n "$PRE_PUSH_HOOK" >/dev/null 2>&1; then
  printf '  ERROR: %s failed bash -n; refusing to wire M-11\n' "$PRE_PUSH_HOOK" >&2
  exit 1
else
  if [ "$DRY_RUN" -eq 0 ]; then
    chmod +x "$PRE_PUSH_HOOK"
    EXISTING="$(git config --global --get core.hooksPath 2>/dev/null || true)"
    if [ -z "$EXISTING" ]; then
      git config --global core.hooksPath "$HOOKS_DIR"
      printf '  Set: global core.hooksPath = %s\n' "$HOOKS_DIR"
    elif [ "$EXISTING" = "$HOOKS_DIR" ]; then
      echo "  global core.hooksPath already set (no-op)"
    else
      printf '  ERROR: global core.hooksPath already points elsewhere:\n' >&2
      printf '    current: %s\n' "$EXISTING" >&2
      printf '    revkit:  %s\n' "$HOOKS_DIR" >&2
      printf '  Resolve: git config --global --unset core.hooksPath\n' >&2
      exit 1
    fi
    echo "  M-11 active: pre-push rejects direct/force/unsigned pushes to main + test"
  else
    printf '  [dry-run] would set core.hooksPath = %s\n' "$HOOKS_DIR"
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
