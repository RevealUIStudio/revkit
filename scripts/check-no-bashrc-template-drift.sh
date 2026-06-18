#!/usr/bin/env bash
# check-no-bashrc-template-drift.sh
#
# Drift guard: templates/wsl/bashrc.d/ should be empty (or absent) per the
# 2026-05-16 consolidation. All bashrc.d files live in shell/shellrc.d/ as the single
# source of truth; bootstrap-wsl.sh sources from there directly. See PR
# adding this gate for rationale.
#
# If you need to reintroduce a templated bashrc.d file (because it actually
# benefits from {{PLACEHOLDER}} substitution): remove this gate AND document
# the new placeholder in scripts/render.sh PLACEHOLDER_MAP.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -d templates/wsl/bashrc.d ] && [ -n "$(ls -A templates/wsl/bashrc.d 2>/dev/null)" ]; then
    echo "ERROR: templates/wsl/bashrc.d/ should be empty." >&2
    echo "  All bashrc.d files live in shell/shellrc.d/ as the single source of truth." >&2
    echo "  Files found:" >&2
    ls -la templates/wsl/bashrc.d/ >&2
    exit 1
fi

echo "ok — templates/wsl/bashrc.d/ is empty (no bashrc.d template drift surface)"
exit 0
