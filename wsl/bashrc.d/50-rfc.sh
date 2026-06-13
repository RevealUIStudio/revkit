# rfc — RevFleet Claude launcher: short command + completion (interactive).
#
# The robust implementation lives at /usr/local/bin/rfc.sh (deployed by
# bootstrap-wsl.sh step 1). This file — auto-sourced in managed interactive
# shells via the ~/.bashrc hook — just provides the short `rfc` name and
# tab-completion over ~/revfleet/* repos. See docs/rfc-launcher.md.

rfc() {
  local impl
  if command -v rfc.sh >/dev/null 2>&1; then
    impl="$(command -v rfc.sh)"
  elif [ -x /usr/local/bin/rfc.sh ]; then
    impl=/usr/local/bin/rfc.sh
  else
    echo "rfc: rfc.sh not installed — run bootstrap-wsl.sh" >&2
    return 1
  fi
  "$impl" "$@"
}

_rfc_complete() {
  # Only complete the first argument (the repo name).
  [ "${COMP_CWORD:-0}" -eq 1 ] || return 0
  local root="${REVFLEET_ROOT:-$HOME/revfleet}" cur="${COMP_WORDS[COMP_CWORD]}"
  local d repos=()
  for d in "$root"/*/ "$root"/.*/; do
    [ -e "${d}.git" ] || continue
    d="${d%/}"; repos+=("${d##*/}")
  done
  COMPREPLY=( $(compgen -W "${repos[*]}" -- "$cur") )
}
complete -F _rfc_complete rfc
