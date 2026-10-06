# shellcheck shell=bash
# native-home.sh: install the native control home, then project vendor adapters.
#
# ~/.revealui is the operator control home. Repo .revealui/content is the
# policy reference. Vendor homes (.grok, and .claude only when opted in) are
# projections of that native tree. This file never clones a vendor config
# repo and never invokes the claude CLI.
#
# Claude adapter (off by default):
#   bootstrap.sh --claude-adapter
#   REVKIT_CLAUDE_ADAPTER=1
#
# Test harness (skips privileged bootstrap steps):
#   REVKIT_BOOTSTRAP_ONLY=control

revkit_repo_root() {
  if [ -n "${REVKIT_ROOT:-}" ]; then
    printf '%s\n' "$REVKIT_ROOT"
    return 0
  fi
  if [ -n "${SCRIPT_DIR:-}" ]; then
    printf '%s\n' "$SCRIPT_DIR"
    return 0
  fi
  return 1
}

revkit_native_home() {
  if [ -n "${REVEALUI_NATIVE_HOME:-}" ]; then
    printf '%s\n' "$REVEALUI_NATIVE_HOME"
    return 0
  fi
  printf '%s\n' "${HOME:?}/.revealui"
}

revkit_claude_adapter_on() {
  [ "${REVKIT_CLAUDE_ADAPTER:-0}" = "1" ]
}

# Copy a text file, stripping CR, without clobbering an identical dest.
revkit_copy_file() {
  local src="$1"
  local dest="$2"
  local tmp
  if [ ! -f "$src" ]; then
    printf '  WARNING: missing %s\n' "$src" >&2
    return 0
  fi
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '  [dry-run] would copy %s -> %s\n' "$src" "$dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  sed 's/\r$//' "$src" > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$dest"
  chmod 0644 "$dest"
  printf '  Deployed: %s\n' "$dest"
}

revkit_sync_tree() {
  local src="$1"
  local dest="$2"
  local f rel
  [ -d "$src" ] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    revkit_copy_file "$f" "$dest/$rel"
  done < <(find "$src" -type f -print0)
}

revkit_install_native_templates() {
  local repo native
  repo="$(revkit_repo_root)" || return 1
  native="$(revkit_native_home)"
  revkit_sync_tree "$repo/templates/adapters/grok" "$native/adapters/grok"
  revkit_sync_tree "$repo/templates/adapters/claude" "$native/adapters/claude"
  if [ -f "$repo/templates/grok/config.toml" ]; then
    revkit_copy_file "$repo/templates/grok/config.toml" "$native/adapters/grok/config.toml"
  fi
}

revkit_install_m4() {
  local repo src session dest_root
  repo="$(revkit_repo_root)" || return 1
  src="$repo/shell/bin/m4-sudoers-fs-scanner.js"
  session="$repo/templates/hooks/session-start.js"
  dest_root="$(revkit_native_home)/hooks"
  if [ ! -f "$src" ]; then
    printf '  WARNING: %s not found, M-4 scanner not deployed\n' "$src" >&2
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "  WARNING: node not in PATH, skipping M-4 scanner deploy" >&2
    return 0
  fi
  if ! node --check "$src" >/dev/null 2>&1; then
    printf '  ERROR: %s failed node --check; refusing to deploy\n' "$src" >&2
    exit 1
  fi
  if [ -f "$session" ] && ! node --check "$session" >/dev/null 2>&1; then
    printf '  ERROR: %s failed node --check; refusing to deploy\n' "$session" >&2
    exit 1
  fi
  revkit_copy_file "$src" "$dest_root/m4-sudoers-fs-scanner.js"
  if [ -f "$session" ]; then
    revkit_copy_file "$session" "$dest_root/session-start.js"
  fi
  echo "  M-4 scanner native path: $dest_root/m4-sudoers-fs-scanner.js"
  echo "  Adapters invoke that path. The script is not copied into a vendor home."
}

revkit_project_grok_adapter() {
  local native dest hook tmpl
  native="$(revkit_native_home)"
  dest="${GROK_HOME:-$HOME/.grok}"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '  [dry-run] would project %s/hooks from %s/adapters/grok\n' "$dest" "$native"
    printf '  [dry-run] would seed Grok [compat.claude] defaults into %s/config.toml\n' "$dest"
    return 0
  fi
  hook="$native/adapters/grok/hooks/m4-sudoers-fs-scan.json"
  if [ -f "$hook" ]; then
    revkit_copy_file "$hook" "$dest/hooks/m4-sudoers-fs-scan.json"
  fi
  tmpl="$native/adapters/grok/config.toml"
  if [ ! -f "$tmpl" ]; then
    return 0
  fi
  # shellcheck disable=SC1091
  . "$(revkit_repo_root)/shell/lib/grok-attach.sh"
  REVEALUI_NATIVE_HOME="$native" rfg_seed_grok_compat
  echo "  Grok config: [compat.claude] hooks, mcps, and sessions stay off unless set"
}

revkit_project_claude_adapter() {
  local native dest
  if ! revkit_claude_adapter_on; then
    echo "  Claude adapter: off (pass --claude-adapter or set REVKIT_CLAUDE_ADAPTER=1)"
    return 0
  fi
  native="$(revkit_native_home)/adapters/claude"
  dest="${REVKIT_CLAUDE_HOME:-$HOME/.claude}"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '  [dry-run] would project %s from %s\n' "$dest" "$native"
    return 0
  fi
  echo "  Claude adapter: projecting $dest from $native"
  echo "  Projection only. Not a vendor config repo, and the claude CLI is not run."
  revkit_sync_tree "$native" "$dest"
}

revkit_link_fleet() {
  local link_sh repo rest profiles_csv mode target_dir editor
  local -a profile_args editors
  if [ -z "${REVEALFLEET_ROOT:-}" ] && [ -n "${_FLEET_PIN:-}" ]; then
    REVEALFLEET_ROOT="$_FLEET_PIN"
  fi
  if [ -z "${REVEALFLEET_ROOT:-}" ] && type rfg_resolve_fleet_root >/dev/null 2>&1; then
    local rc=0
    REVEALFLEET_ROOT="$(rfg_resolve_fleet_root)" || rc=$?
    if [ "$rc" -eq 78 ]; then
      exit 78
    fi
    if [ "$rc" -ne 0 ]; then
      REVEALFLEET_ROOT=""
    fi
  fi
  if [ -z "${REVEALFLEET_ROOT:-}" ]; then
    echo "  WARNING: fleet root unresolved, skipping revcon link (set REVEALFLEET_ROOT)" >&2
    return 0
  fi
  link_sh="$REVEALFLEET_ROOT/revcon/link.sh"
  if [ ! -f "$link_sh" ]; then
    printf '  WARNING: %s not found, skipping (clone the revcon repo first)\n' "$link_sh" >&2
    return 0
  fi

  # Native editor first. Vendor editors are projections of that tree.
  # link.sh already defaults to revealui; the flag is explicit so a vendor
  # editor cannot become the first write.
  local -a fleet_targets=(
    "revealui:revealfleet,revealui:copy"
    "revdev:revealfleet:copy"
    "revvault:revealfleet:copy"
    "revcon:revealfleet:copy"
    "revforge:revealfleet:copy"
    "revskills:revealfleet:copy"
    "revkit:revealfleet:copy"
  )
  editors=(revealui cursor zed vscode claude agents)

  for entry in "${fleet_targets[@]}"; do
    repo="${entry%%:*}"
    rest="${entry#*:}"
    profiles_csv="${rest%%:*}"
    mode="symlink"
    case "$rest" in
      *:*) mode="${rest#*:}" ;;
    esac
    target_dir="${REVEALFLEET_ROOT}/$repo"
    if [ ! -d "$target_dir" ]; then
      printf '  [skip] %s not found at %s\n' "$repo" "$target_dir"
      continue
    fi
    profile_args=()
    local p
    IFS=',' read -ra _profiles <<< "$profiles_csv"
    for p in "${_profiles[@]}"; do
      profile_args+=("--profile" "$p")
    done
    for editor in "${editors[@]}"; do
      printf '  [%s] editor %s profiles %s (mode %s)\n' "$repo" "$editor" "$profiles_csv" "$mode"
      if [ "${DRY_RUN:-0}" -eq 1 ]; then
        printf '  [dry-run] would run revcon/link.sh --editor %s --mode %s for %s\n' \
          "$editor" "$mode" "$repo"
      else
        bash "$link_sh" --target "$target_dir" --editor "$editor" --mode "$mode" \
          "${profile_args[@]}" 2>&1 | sed 's/^/    /'
      fi
    done
  done
  echo "  Done."
}

revkit_bootstrap_control_layer() {
  echo "[7] Writing native control home (~/.revealui)..."
  revkit_install_native_templates
  if revkit_claude_adapter_on; then
    echo "  Claude adapter requested. It projects pointers from the native home."
  else
    echo "  Claude adapter: off (pass --claude-adapter or set REVKIT_CLAUDE_ADAPTER=1)"
  fi

  echo "[8] Deploying M-4 scanner to the native hooks directory..."
  revkit_install_m4
  revkit_project_grok_adapter
  revkit_project_claude_adapter

  echo "[9] Wiring fleet rules via revcon (native first, then vendor projections)..."
  revkit_link_fleet
}
