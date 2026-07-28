#!/usr/bin/env bash
# fleet-workflow-health.sh — watcher-of-watchers (GAP-420).
#
# For each fleet repo, flags any GitHub Actions workflow whose N most recent
# COMPLETED runs are ALL "failure". A single red run never trips this — the
# check only fires on N-deep consecutive failure, because the status repo's
# Update Template workflow failed every run for 3+ weeks (2026-07-05 through
# 2026-07-25) before anyone noticed (GAP-420). Nothing was watching it.
#
# See .github/workflows/fleet-workflow-health.yml for the schedule + alert
# path: a failing run of THAT workflow generates GitHub's own workflow-failure
# email to the owner, which is the alert channel here — there is no separate
# notification wiring in this script.
#
# Usage:
#   bash scripts/fleet-workflow-health.sh             # scan the fleet; exit 1 if any repo is unhealthy
#   bash scripts/fleet-workflow-health.sh --self-test  # exercise the predicate against canned JSON, no network
#
# Requires: gh (authenticated with enough scope to read each repo's Actions
# runs — see the workflow file header for what the CI token can actually see),
# jq.

set -uo pipefail

OWNER="RevealUIStudio"
CONSECUTIVE_FAILURES=3
REPOS=(revealui revdev revkit revskills revvault revcon agency revforge status)

# ---------------------------------------------------------------------------
# unhealthy_workflows <n>
#
# Reads one repo's `gh api .../actions/runs` JSON response on stdin (the
# {"total_count":N,"workflow_runs":[...]} shape) and, for each distinct
# workflow_id present, emits one TSV line:
#   <workflow name>\t<unhealthy: true|false>\t<comma-joined last-N conclusions>
#
# "unhealthy" requires the workflow to have at least N COMPLETED runs AND all
# N most recent completed runs to have concluded "failure". A workflow with
# fewer than N completed runs, or any conclusion other than "failure" among
# its N most recent, is never flagged — this is what keeps a single red run
# (or a still-flaky one) from false-alarming.
# ---------------------------------------------------------------------------
unhealthy_workflows() {
  local n="$1"
  jq -r --argjson n "$n" '
    .workflow_runs
    | group_by(.workflow_id)
    | map({
        name: (.[0].name // .[0].path // "workflow-\(.[0].workflow_id)"),
        recent: ([ .[] | select(.status == "completed") ] | sort_by(.created_at) | reverse | .[0:$n])
      })
    | map({
        name,
        unhealthy: ((.recent | length) == $n and (.recent | all(.conclusion == "failure"))),
        conclusions: (.recent | map(.conclusion // "null") | join(","))
      })
    | .[]
    | [.name, (.unhealthy | tostring), .conclusions]
    | @tsv
  '
}

print_row() {
  printf '%-14s  %-36s  %-9s  %s\n' "$1" "$2" "$3" "$4"
}

run_self_test() {
  # Canned fixture, no network: four workflows exercising the predicate's
  # boundary conditions.
  #   always-red  -> 3 completed runs, all failure           => UNHEALTHY
  #   flaky       -> 3 completed runs, 2 failure + 1 success => healthy
  #   one-red     -> 1 completed run, failure (not N-deep)   => healthy
  #   in-progress -> 0 completed runs                        => healthy
  local fixture
  fixture=$(cat <<'JSON'
{
  "workflow_runs": [
    {"workflow_id": 1, "name": "always-red", "status": "completed", "conclusion": "failure", "created_at": "2026-07-20T00:00:00Z"},
    {"workflow_id": 1, "name": "always-red", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T00:00:00Z"},
    {"workflow_id": 1, "name": "always-red", "status": "completed", "conclusion": "failure", "created_at": "2026-07-18T00:00:00Z"},
    {"workflow_id": 1, "name": "always-red", "status": "completed", "conclusion": "success", "created_at": "2026-07-17T00:00:00Z"},

    {"workflow_id": 2, "name": "flaky", "status": "completed", "conclusion": "failure", "created_at": "2026-07-20T00:00:00Z"},
    {"workflow_id": 2, "name": "flaky", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T00:00:00Z"},
    {"workflow_id": 2, "name": "flaky", "status": "completed", "conclusion": "failure", "created_at": "2026-07-18T00:00:00Z"},

    {"workflow_id": 3, "name": "one-red", "status": "completed", "conclusion": "failure", "created_at": "2026-07-20T00:00:00Z"},

    {"workflow_id": 4, "name": "in-progress", "status": "in_progress", "conclusion": null, "created_at": "2026-07-20T00:00:00Z"}
  ]
}
JSON
)

  local pass=0 fail=0
  while IFS=$'\t' read -r name unhealthy conclusions; do
    case "$name" in
      always-red)
        if [ "$unhealthy" = "true" ]; then
          echo "ok    $name -> UNHEALTHY ($conclusions)"; pass=$((pass + 1))
        else
          echo "FAIL  $name -> expected unhealthy=true, got $unhealthy ($conclusions)"; fail=$((fail + 1))
        fi
        ;;
      flaky)
        if [ "$unhealthy" = "false" ]; then
          echo "ok    $name -> healthy, one non-failure in the last $CONSECUTIVE_FAILURES ($conclusions)"; pass=$((pass + 1))
        else
          echo "FAIL  $name -> expected unhealthy=false, got $unhealthy ($conclusions)"; fail=$((fail + 1))
        fi
        ;;
      one-red)
        if [ "$unhealthy" = "false" ]; then
          echo "ok    $name -> healthy, only 1 completed run ($conclusions)"; pass=$((pass + 1))
        else
          echo "FAIL  $name -> expected unhealthy=false (insufficient depth), got $unhealthy ($conclusions)"; fail=$((fail + 1))
        fi
        ;;
      in-progress)
        if [ "$unhealthy" = "false" ]; then
          echo "ok    $name -> healthy, no completed runs yet ($conclusions)"; pass=$((pass + 1))
        else
          echo "FAIL  $name -> expected unhealthy=false, got $unhealthy ($conclusions)"; fail=$((fail + 1))
        fi
        ;;
      *)
        echo "FAIL  unexpected workflow in fixture output: $name"; fail=$((fail + 1))
        ;;
    esac
  done < <(printf '%s' "$fixture" | unhealthy_workflows "$CONSECUTIVE_FAILURES")

  echo
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

run_scan() {
  local any_unhealthy=0
  print_row "REPO" "WORKFLOW" "STATUS" "LAST $CONSECUTIVE_FAILURES CONCLUSIONS"
  print_row "----" "--------" "------" "-----------------------"

  for repo in "${REPOS[@]}"; do
    local errfile json rows
    errfile="$(mktemp)"
    if ! json="$(gh api "repos/$OWNER/$repo/actions/runs?per_page=30" 2>"$errfile")"; then
      local err
      err="$(cat "$errfile")"
      rm -f "$errfile"
      case "$err" in
        *"404"*|*"Not Found"*|*"403"*|*"Forbidden"*)
          print_row "$repo" "-" "SKIPPED" "no Actions access (private or restricted; relies on GitHub's failure emails)"
          ;;
        *)
          print_row "$repo" "-" "SKIPPED" "gh api error: ${err:0:60}"
          ;;
      esac
      continue
    fi
    rm -f "$errfile"

    rows="$(printf '%s' "$json" | unhealthy_workflows "$CONSECUTIVE_FAILURES")"
    if [ -z "$rows" ]; then
      print_row "$repo" "-" "OK" "no workflow has $CONSECUTIVE_FAILURES+ completed runs yet"
      continue
    fi

    while IFS=$'\t' read -r name unhealthy conclusions; do
      if [ "$unhealthy" = "true" ]; then
        print_row "$repo" "$name" "UNHEALTHY" "$conclusions"
        any_unhealthy=1
      else
        print_row "$repo" "$name" "ok" "$conclusions"
      fi
    done <<< "$rows"
  done

  return "$any_unhealthy"
}

case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  "")
    run_scan
    exit $?
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
