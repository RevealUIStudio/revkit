#!/usr/bin/env bash
# check-no-client-names.sh
#
# Watchlist gate for client / buyer / end-client terms that must not appear
# in public artifacts. Companion to:
#   scripts/check-no-private-leaks.sh  paths, hostnames, machine homes
#   scripts/check-client-leaks.sh      long-lived literals kept in this script
#
# This file never embeds watchlist terms. Load from (first found):
#   1. $CLIENT_NAME_WATCHLIST_FILE
#   2. .client-name-watchlist.local under repo root
#   3. $CLIENT_NAME_PATTERNS (newline or | separated)
#
# If no watchlist: WARN + exit 0 (gate inactive) so public CI without a secret
# does not false-fail. Layer A (bot daily org audit) still runs. Set
# CLIENT_NAME_WATCHLIST_REQUIRED=1 to exit 2 when the watchlist is missing.
#
# The hardcoded scanner (check-client-leaks.sh) stays. Use this gate for
# operator-local or CI-secret terms that must not live in git.
#
# Exit 0 on clean (or inactive). Exit 1 on any violation. Exit 2 on setup error.
#
# Usage:
#   bash scripts/check-no-client-names.sh                     # scan repo root
#   bash scripts/check-no-client-names.sh <path> [<path>...]  # scan explicit paths
#   LEAK_JSON=1 bash scripts/check-no-client-names.sh         # machine-readable
#
# Safe to rerun; read-only. Do not commit real watchlist terms to public git.
# Design: docs/client-name-public-github.md

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_PATHS=("$@")
[[ ${#SCAN_PATHS[@]} -eq 0 ]] && SCAN_PATHS=("$REPO_ROOT")

for _path in "${SCAN_PATHS[@]}"; do
  if [[ ! -e "$_path" ]]; then
    echo "[client-name-check] error: scan path not found: $_path" >&2
    exit 2
  fi
done
unset _path

if ! command -v grep >/dev/null 2>&1; then
  echo "[client-name-check] error: grep not found on PATH" >&2
  exit 2
fi

# Same exclude set as check-no-private-leaks.sh (build/dev artifacts + self).
# .client-name-watchlist.local holds the terms on purpose, so it is not a hit.
EXCLUDE_DIRS=(node_modules .git dist build .next .turbo .pnpm coverage target .direnv .nyc_output)
EXCLUDE_FILES=(
  pnpm-lock.yaml package-lock.json yarn.lock Cargo.lock
  check-no-client-names.sh
  check-no-private-leaks.sh
  client-name-watchlist.example
  .client-name-watchlist.local
  .git
  '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webp' '*.pdf' '*.zip' '*.tar.gz' '*.tgz'
  '*.ico' '*.woff' '*.woff2' '*.ttf' '*.otf'
)

grep_excludes=()
for d in "${EXCLUDE_DIRS[@]}"; do
  grep_excludes+=(--exclude-dir="$d")
done
for f in "${EXCLUDE_FILES[@]}"; do
  grep_excludes+=(--exclude="$f")
done

# --- Load watchlist patterns (no real terms in this source file) ---
declare -a PATTERNS=()
WATCHLIST_SOURCE=""
WATCHLIST_FILE_SKIP=""

load_patterns_from_file() {
  local file="$1"
  local raw line
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    # Strip trailing CR (Windows watchlist files).
    raw="${raw%$'\r'}"
    # Full-line comments.
    [[ "$raw" =~ ^[[:space:]]*# ]] && continue
    # Strip inline comments after #
    line="${raw%%#*}"
    # Trim whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    PATTERNS+=("$line")
  done < "$file"
}

if [[ -n "${CLIENT_NAME_WATCHLIST_FILE:-}" ]]; then
  if [[ ! -f "$CLIENT_NAME_WATCHLIST_FILE" ]]; then
    echo "[client-name-check] error: CLIENT_NAME_WATCHLIST_FILE not found: $CLIENT_NAME_WATCHLIST_FILE" >&2
    exit 2
  fi
  load_patterns_from_file "$CLIENT_NAME_WATCHLIST_FILE"
  WATCHLIST_SOURCE="CLIENT_NAME_WATCHLIST_FILE=$CLIENT_NAME_WATCHLIST_FILE"
  WATCHLIST_FILE_SKIP="$CLIENT_NAME_WATCHLIST_FILE"
elif [[ -f "$REPO_ROOT/.client-name-watchlist.local" ]]; then
  load_patterns_from_file "$REPO_ROOT/.client-name-watchlist.local"
  WATCHLIST_SOURCE="$REPO_ROOT/.client-name-watchlist.local"
  WATCHLIST_FILE_SKIP="$REPO_ROOT/.client-name-watchlist.local"
elif [[ -n "${CLIENT_NAME_PATTERNS:-}" ]]; then
  # Newline or | separated.
  _tmp="${CLIENT_NAME_PATTERNS}"
  if [[ "$_tmp" == *$'\n'* ]]; then
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      line="${raw%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" ]] && continue
      PATTERNS+=("$line")
    done <<< "$_tmp"
  else
    IFS='|' read -ra _parts <<< "$_tmp"
    for raw in "${_parts[@]}"; do
      line="${raw#"${raw%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" ]] && continue
      PATTERNS+=("$line")
    done
  fi
  unset _tmp _parts raw line
  WATCHLIST_SOURCE="CLIENT_NAME_PATTERNS"
fi

if [[ ${#PATTERNS[@]} -eq 0 ]]; then
  if [[ "${CLIENT_NAME_WATCHLIST_REQUIRED:-}" == "1" ]]; then
    echo "[client-name-check] error: no watchlist loaded and CLIENT_NAME_WATCHLIST_REQUIRED=1" >&2
    echo "[client-name-check] set CLIENT_NAME_WATCHLIST_FILE, add .client-name-watchlist.local, or CLIENT_NAME_PATTERNS" >&2
    exit 2
  fi
  echo "[client-name-check] WARN: no watchlist found; gate inactive (exit 0)." >&2
  echo "[client-name-check] Layer A (bot daily org audit) still runs. To activate Layer B:" >&2
  echo "[client-name-check]   copy templates/client-name-watchlist.example -> .client-name-watchlist.local" >&2
  echo "[client-name-check]   or set CLIENT_NAME_WATCHLIST_FILE / CLIENT_NAME_PATTERNS" >&2
  if [[ -n "${LEAK_JSON:-}" ]]; then
    printf '{"violations":0,"inactive":true,"entries":[]}\n'
  fi
  exit 0
fi

# A watchlist file inside the scan tree contains the terms on purpose.
is_watchlist_source_file() {
  local file="$1"
  local skip="$WATCHLIST_FILE_SKIP"
  [[ -z "$skip" ]] && return 1
  file="${file#./}"
  skip="${skip#./}"
  [[ "$file" == "$skip" ]] && return 0
  [[ "$file" == "$REPO_ROOT/$skip" ]] && return 0
  [[ "$REPO_ROOT/$file" == "$skip" ]] && return 0
  return 1
}

# Escape a literal string for use as an ERE (watchlist terms are literals).
# `]` is first inside the bracket expression so it is literal.
ere_escape() {
  printf '%s' "$1" | sed -e 's/[][\\.^$|?*+(){}]/\\&/g'
}

violations=0
json_entries=()

for term in "${PATTERNS[@]}"; do
  regex="$(ere_escape "$term")"
  # -H always prints the path. A single explicit file otherwise omits it,
  # which breaks hit parsing and watchlist self-skip.
  # -r recursive, -E ERE, -I skip binary, -n line numbers, -i case-insensitive.
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"
    rest_="${hit#*:}"
    line="${rest_%%:*}"
    content="${rest_#*:}"

    is_watchlist_source_file "$file" && continue

    if [[ -n "${LEAK_JSON:-}" ]]; then
      if command -v jq >/dev/null 2>&1; then
        json_entries+=("$(jq -cn --arg tag "client-name" --arg file "$file" --arg line "$line" --arg reason "watchlist term match" --arg content "$content" \
          '{tag:$tag, file:$file, line:($line|tonumber), reason:$reason, content:$content}')")
      else
        safe_content="${content//\\/\\\\}"
        safe_content="${safe_content//\"/\\\"}"
        safe_content="${safe_content//$'\n'/\\n}"
        safe_content="${safe_content//$'\t'/\\t}"
        json_entries+=("{\"tag\":\"client-name\",\"file\":\"$file\",\"line\":$line,\"reason\":\"watchlist term match\",\"content\":\"$safe_content\"}")
      fi
    else
      printf '[LEAK:client-name] %s:%s - watchlist term match\n  -> %s\n' "$file" "$line" "$content"
    fi
    violations=$((violations+1))
  done < <(grep -rHEIni "${grep_excludes[@]}" -- "$regex" "${SCAN_PATHS[@]}" 2>/dev/null || true)
done

if [[ -n "${LEAK_JSON:-}" ]]; then
  if command -v jq >/dev/null 2>&1; then
    source_json="$(jq -cn --arg s "$WATCHLIST_SOURCE" '$s')"
  else
    source_json="$(printf '"%s"' "${WATCHLIST_SOURCE//\"/\\\"}")"
  fi
  printf '{"violations":%d,"inactive":false,"source":%s,"entries":[%s]}\n' \
    "$violations" \
    "$source_json" \
    "$(IFS=,; echo "${json_entries[*]:-}")"
fi

if (( violations > 0 )); then
  [[ -z "${LEAK_JSON:-}" ]] && echo "[client-name-check] FAIL - $violations violation(s). Fix before publishing." >&2
  exit 1
fi

[[ -z "${LEAK_JSON:-}" ]] && echo "[client-name-check] OK - no watchlist terms across: ${SCAN_PATHS[*]} (source: $WATCHLIST_SOURCE)"
exit 0
