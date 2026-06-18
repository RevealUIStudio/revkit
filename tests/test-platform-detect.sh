#!/usr/bin/env bash
# tests/test-platform-detect.sh — fixture-driven unit tests for lib/platform.sh.
#
# Drives detection with synthetic env/marker snapshots so classification is
# asserted WITHOUT the real OS. The decisive WSL signal is the /run/WSL directory;
# fixtures toggle it via REVKIT_WSL_RUN_DIR pointing at an existing/nonexistent dir.
# Fixtures contain only synthetic descriptors — no real hostnames/usernames.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FIX="$HERE/platform-fixtures"
PLATFORM="$ROOT/lib/platform.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
present_dir="$tmp/run-wsl-present"
mkdir -p "$present_dir"
absent_dir="$tmp/run-wsl-absent"   # intentionally never created

pass=0
fail=0

read_field() {
  local file="$1" key="$2" line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*) printf '%s' "${line#*=}"; return 0 ;;
    esac
  done < "$file"
  printf ''
}

detect() {
  # detect runs platform.sh in a clean subshell and echoes REVKIT_OS; stderr -> $1.
  local errfile="$1"; shift
  env "$@" REVKIT_WSL_INTEROP_FILE="$absent_dir/none" \
    bash -c '. "$0"; printf "%s" "${REVKIT_OS:-}"' "$PLATFORM" 2>"$errfile"
}

# --- Detection-scenario fixtures ---
for dir in "$FIX"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  uname_s="$(read_field "$dir/env" uname_s)"
  wsl_run="$(read_field "$dir/env" wsl_run)"
  expected="$(read_field "$dir/env" expected)"
  case "$wsl_run" in present) run_dir="$present_dir" ;; *) run_dir="$absent_dir" ;; esac

  got="$(detect "$tmp/err" REVKIT_OS='' REVKIT_UNAME_S="$uname_s" REVKIT_WSL_RUN_DIR="$run_dir")"
  if [ "$got" = "$expected" ]; then
    printf 'ok    %-34s -> %s\n' "$name" "$got"; pass=$((pass + 1))
  else
    printf 'FAIL  %-34s -> got "%s" expected "%s"\n' "$name" "$got" "$expected"; fail=$((fail + 1))
  fi
done

# --- Hard-override fixtures (whitespace embedded HERE, not in a file, so it
#     cannot be stripped by an editor/git): trim + lowercase + reject. ---
check_override() {
  local name="$1" val="$2" exp="$3" out
  out="$(detect "$tmp/oerr" REVKIT_OS="$val")"
  if [ "$exp" = ERROR ]; then
    if [ -z "$out" ] && grep -q 'invalid REVKIT_OS' "$tmp/oerr"; then
      printf 'ok    %-34s -> rejected\n' "$name"; pass=$((pass + 1))
    else
      printf 'FAIL  %-34s -> expected rejection; got "%s"\n' "$name" "$out"; fail=$((fail + 1))
    fi
  else
    if [ "$out" = "$exp" ]; then
      printf 'ok    %-34s -> %s\n' "$name" "$out"; pass=$((pass + 1))
    else
      printf 'FAIL  %-34s -> got "%s" expected "%s"\n' "$name" "$out" "$exp"; fail=$((fail + 1))
    fi
  fi
}
check_override "override-uppercase"        "WSL"                   "wsl"
check_override "override-trailing-space"   "wsl "                  "wsl"
check_override "override-tab-suffix"       "$(printf 'macos\t')"   "macos"
check_override "override-invalid-windows"  "windows"               "ERROR"

printf -- '----\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
