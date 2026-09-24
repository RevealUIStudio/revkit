#!/usr/bin/env bash
# kill-audit-storms: clear leftover laptop audit du/find storms that wedge WSL I/O.
# Only known audit patterns, and only processes older than AUDIT_STORM_MIN_AGE_SEC
# (default 600). Never kills live grok, the current rfg process, this sweeper,
# or unrelated user work.
#
# AUDIT_STORM_MIN_AGE_SEC   default 600 (standalone). rfg preflight passes 120.
# AUDIT_STORM_DRY_RUN=1     print candidates, do not signal them.
# AUDIT_STORM_REPORT_ONLY=1 same as dry-run.
# RFG_STORM_PROTECT_PIDS    extra PIDs to leave alone (the calling rfg).
# shellcheck shell=bash
set -euo pipefail

# [[dd-]hh:]mm:ss -> seconds. Empty or junk -> 0.
audit_storm_etime_to_sec() {
  local e="${1:-}" d=0 h=0 m=0 s=0
  local -a parts=()
  if [ -z "$e" ]; then
    printf '0\n'
    return 0
  fi
  if [[ "$e" == *-* ]]; then
    d="${e%%-*}"
    e="${e#*-}"
  fi
  IFS=: read -ra parts <<< "$e"
  case "${#parts[@]}" in
    3) h="${parts[0]}"; m="${parts[1]}"; s="${parts[2]}" ;;
    2) m="${parts[0]}"; s="${parts[1]}" ;;
    1) s="${parts[0]}" ;;
  esac
  d="${d//[^0-9]/}"
  h="${h//[^0-9]/}"
  m="${m//[^0-9]/}"
  s="${s//[^0-9]/}"
  printf '%s\n' "$((10#${d:-0} * 86400 + 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${s:-0}))"
}

# True when this pid/cmdline must not be signaled.
# Case arms stay separate. A combined pattern with a quoted grok* glob is a bash syntax error.
# find of ~/.grok does not contain bin/grok, so those audits still qualify.
audit_storm_pid_protected() {
  local pid="$1" cmd="$2" base p home_rfg
  local -a extra=()
  [ "$pid" = "$$" ] && return 0
  if [ -n "${PPID:-}" ] && [ "$pid" = "$PPID" ]; then
    return 0
  fi
  if [ -n "${RFG_STORM_PROTECT_PIDS:-}" ]; then
    # shellcheck disable=SC2206
    extra=(${RFG_STORM_PROTECT_PIDS})
    for p in "${extra[@]}"; do
      [ "$pid" = "$p" ] && return 0
    done
  fi
  case "$cmd" in
    *kill-audit-storms*) return 0 ;;
    *rfg.sh*) return 0 ;;
    */usr/local/bin/rfg*) return 0 ;;
    *bin/grok*) return 0 ;;
  esac
  if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
    home_rfg="${HOME}/.local/bin/rfg"
    case "$cmd" in
      *"$home_rfg"*) return 0 ;;
    esac
  fi
  # Bare argv0 (grok on PATH, rfg with no path) still must not be signaled.
  base="${cmd%% *}"
  base="${base##*/}"
  case "$base" in
    grok|rfg|rfg.sh|kill-audit-storms|kill-audit-storms.sh) return 0 ;;
  esac
  return 1
}

# Known orphan audit cmdlines only.
# Home path comes from $HOME (home-wide du, find of home / .grok / .claude / .local).
# Pack markers are the audit strings those leftovers leave in argv.
audit_storm_cmd_match() {
  local cmd="$1" home marker
  case "$cmd" in
    *'REVFLEET HARDCODE'*|*'WHO CREATES'*|*'TOP-LEVEL DETAILED'*|*'HOME TOP-LEVEL'*|*'fleet-identity'*)
      return 0
      ;;
  esac
  home="${HOME:-}"
  if [ -n "$home" ] && [ "$home" != "/" ]; then
    case "$cmd" in
      *"du -sh ${home}"*|*"find ${home}"*) return 0 ;;
    esac
    marker="$(basename "$home")-audit"
    case "$cmd" in
      *"$marker"*) return 0 ;;
    esac
  fi
  return 1
}

# D-state leftovers use the wider corrected filter: any du -sh, find of $HOME,
# a relative find ., and the home audit marker. Age and rfg/grok skips still apply.
audit_storm_dstate_cmd_match() {
  local cmd="$1" home marker
  case "$cmd" in
    *'du -sh'*) return 0 ;;
    *'find .'*) return 0 ;;
  esac
  home="${HOME:-}"
  if [ -n "$home" ] && [ "$home" != "/" ]; then
    case "$cmd" in
      *"find ${home}"*) return 0 ;;
    esac
    marker="$(basename "$home")-audit"
    case "$cmd" in
      *"$marker"*) return 0 ;;
    esac
  fi
  return 1
}

audit_storm_ps_etime() {
  ps -eo pid=,etime=,cmd= 2>/dev/null || ps -axo pid=,etime=,command= 2>/dev/null || true
}

audit_storm_ps_d() {
  ps -eo pid=,stat=,etime=,cmd= 2>/dev/null || ps -axo pid=,stat=,etime=,command= 2>/dev/null || true
}

# pid, etime, cmd  (tab-separated). Last field keeps the rest of the cmdline.
audit_storm_rows_etime() {
  audit_storm_ps_etime | awk '
    $1 ~ /^[0-9]+$/ && NF >= 2 {
      pid=$1
      et=$2
      $1=""
      $2=""
      sub(/^[[:space:]]+/, "", $0)
      printf "%s\t%s\t%s\n", pid, et, $0
    }
  ' || true
}

# pid, stat, etime, cmd
audit_storm_rows_d() {
  audit_storm_ps_d | awk '
    $1 ~ /^[0-9]+$/ && NF >= 3 {
      pid=$1
      st=$2
      et=$3
      $1=""
      $2=""
      $3=""
      sub(/^[[:space:]]+/, "", $0)
      printf "%s\t%s\t%s\t%s\n", pid, st, et, $0
    }
  ' || true
}

# Matching D-state audit processes still present (any age). Printed for the preflight warning.
audit_storm_dstate_lines() {
  local pid stat et cmd
  while IFS=$'\t' read -r pid stat et cmd; do
    [ -n "${pid:-}" ] || continue
    [[ "${stat:-}" == *D* ]] || continue
    audit_storm_dstate_cmd_match "${cmd:-}" || continue
    printf '%s %s %s %s\n' "$pid" "$stat" "$et" "$cmd"
  done < <(audit_storm_rows_d)
  return 0
}

audit_storm_min_age() {
  local min="${AUDIT_STORM_MIN_AGE_SEC:-600}"
  case "$min" in
    ''|*[!0-9]*) min=600 ;;
  esac
  printf '%s\n' "$min"
}

audit_storm_main() {
  local min dry report killed warned_d
  local pid et cmd age stat rest
  local -a candidates=() uniq=()
  local c p u found
  min="$(audit_storm_min_age)"
  dry="${AUDIT_STORM_DRY_RUN:-0}"
  report="${AUDIT_STORM_REPORT_ONLY:-0}"
  killed=0
  warned_d=0

  while IFS=$'\t' read -r pid et cmd; do
    [ -n "${pid:-}" ] || continue
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    age="$(audit_storm_etime_to_sec "${et:-}")"
    [ "$age" -lt "$min" ] && continue
    audit_storm_pid_protected "$pid" "${cmd:-}" && continue
    audit_storm_cmd_match "${cmd:-}" || continue
    candidates+=("$pid|$et|$cmd")
  done < <(audit_storm_rows_etime)

  while IFS=$'\t' read -r pid stat et cmd; do
    [ -n "${pid:-}" ] || continue
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ "${stat:-}" == *D* ]] || continue
    age="$(audit_storm_etime_to_sec "${et:-}")"
    [ "$age" -lt "$min" ] && continue
    audit_storm_pid_protected "$pid" "${cmd:-}" && continue
    if audit_storm_dstate_cmd_match "${cmd:-}"; then
      candidates+=("$pid|$et|$cmd")
    else
      warned_d=$((warned_d + 1))
    fi
  done < <(audit_storm_rows_d)

  if [ "${#candidates[@]}" -gt 0 ]; then
    for c in "${candidates[@]}"; do
      p="${c%%|*}"
      found=0
      if [ "${#uniq[@]}" -gt 0 ]; then
        for u in "${uniq[@]}"; do
          if [ "${u%%|*}" = "$p" ]; then
            found=1
            break
          fi
        done
      fi
      [ "$found" -eq 1 ] && continue
      uniq+=("$c")
    done
  fi

  if [ "${#uniq[@]}" -eq 0 ]; then
    echo "kill-audit-storms: none (min_age=${min}s)"
    return 0
  fi

  echo "kill-audit-storms: ${#uniq[@]} candidate(s) older than ${min}s"
  for c in "${uniq[@]}"; do
    pid="${c%%|*}"
    rest="${c#*|}"
    et="${rest%%|*}"
    cmd="${rest#*|}"
    echo "  pid=$pid etime=$et cmd=$cmd"
    if [ "$report" = 1 ] || [ "$dry" = 1 ]; then
      continue
    fi
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
    killed=$((killed + 1))
  done

  echo "kill-audit-storms: killed=$killed dry_run=$dry report_only=$report other_D_warned=$warned_d"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  audit_storm_main
fi
