#!/usr/bin/env bash
# shellcheck shell=bash
# lib/platform.sh — single source of OS detection + capability predicates for RevKit.
#
# Sets REVKIT_OS to exactly one of: wsl | linux | macos.
#   wsl   — Linux under WSL2; RevKit runs WSL-only host ops (systemd masking, drive mounts, wsl.exe interop)
#   linux — NATIVE (non-WSL) Linux desktop/server/container; those host ops would DAMAGE it
#   macos — macOS (Darwin)
#
# CORRECTNESS PROPERTY (the reason this file exists): a native (non-WSL) system —
# INCLUDING a container running ON a WSL host — must NEVER be classified `wsl`,
# because RevKit would then run destructive WSL-only host operations.
#
# WSL is detected by ONE decisive signal: the /run/WSL directory, created per-distro
# by WSL on a per-boot tmpfs. Unlike the tempting alternatives, /run/WSL is:
#   * NOT an inheritable env var  — a leaked WSL_DISTRO_NAME (SSH SendEnv, tmux, CI
#                                   matrix, `docker run -e`) cannot fake it;
#   * NOT a host-global mount     — it is absent inside containers, unlike the shared
#                                   /proc/sys/fs/binfmt_misc/WSLInterop binfmt entry;
#   * NOT a kernel version string — a native box whose kernel string contains
#                                   "microsoft"/"WSL" cannot fake it, and a real WSL
#                                   box with a custom kernel (no token) is still detected.
# WSL1 has no /run/WSL and classifies as `linux`; RevKit's host ops target WSL2.
#
# Testability (CI fixtures drive detection without the real OS):
#   REVKIT_OS               — hard override; trimmed + lowercased + validated to wsl|linux|macos (else error)
#   REVKIT_UNAME_S          — value used instead of `uname -s`
#   REVKIT_WSL_RUN_DIR      — directory tested instead of /run/WSL (the decisive marker)
#   REVKIT_WSL_INTEROP_FILE — path for revkit_has_wsl_interop() (capability only; NOT classification)
#
# Idempotent. POSIX-clean (only bashism is `local`, inside called functions — safe under zsh sourcing).

_revkit_detect_os() {
  # Hard override: validate + normalize (trim whitespace, lowercase). Reject
  # anything not in the contract rather than propagating a silently-inert class.
  if [ -n "${REVKIT_OS:-}" ]; then
    local _override
    _override="$(printf '%s' "$REVKIT_OS" | tr -d '[:space:]' | tr 'A-Z' 'a-z')"
    case "$_override" in
      wsl | linux | macos) printf '%s' "$_override"; return 0 ;;
      *) printf 'platform.sh: invalid REVKIT_OS=%s (must be wsl|linux|macos)\n' "$REVKIT_OS" >&2; return 1 ;;
    esac
  fi

  local uname_s uname_lc wsl_run_dir
  uname_s="${REVKIT_UNAME_S:-$(uname -s 2>/dev/null || printf 'unknown')}"
  uname_lc="$(printf '%s' "$uname_s" | tr 'A-Z' 'a-z')"

  case "$uname_lc" in
    darwin)
      printf 'macos'
      return 0
      ;;
    linux)
      wsl_run_dir="${REVKIT_WSL_RUN_DIR:-/run/WSL}"
      if [ -d "$wsl_run_dir" ]; then
        printf 'wsl'
      else
        printf 'linux'
      fi
      return 0
      ;;
    *)
      # Unknown / other POSIX (e.g. *BSD): native linux-like, never wsl.
      printf 'linux'
      return 0
      ;;
  esac
}

REVKIT_OS="$(_revkit_detect_os)"
export REVKIT_OS

# --- Capability predicates (use as: revkit_is_wsl && ...) ---
revkit_is_wsl()          { [ "${REVKIT_OS:-}" = wsl ]; }
revkit_is_macos()        { [ "${REVKIT_OS:-}" = macos ]; }
revkit_is_linux()        { [ "${REVKIT_OS:-}" = linux ]; }   # native, non-WSL
revkit_is_posix()        { case "${REVKIT_OS:-}" in wsl | linux | macos) return 0 ;; *) return 1 ;; esac; }
revkit_has_systemd()     { [ -d /run/systemd/system ]; }
revkit_has_wsl_interop() {
  local f="${REVKIT_WSL_INTEROP_FILE:-/proc/sys/fs/binfmt_misc/WSLInterop}"
  [ -e "$f" ] || [ -e "${f}-late" ]
}
