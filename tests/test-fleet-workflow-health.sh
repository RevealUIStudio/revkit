#!/usr/bin/env bash
# tests/test-fleet-workflow-health.sh — regression guard for the fleet
# workflow health watcher's consecutive-failure predicate (GAP-420).
#
# Delegates to the script's own --self-test fixture (network-free, canned
# JSON) so this test lands as a CI job alongside the other tests/test-*.sh
# checks without duplicating the fixture.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

bash "$ROOT/scripts/fleet-workflow-health.sh" --self-test
