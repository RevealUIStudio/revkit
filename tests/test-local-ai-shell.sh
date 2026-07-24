#!/usr/bin/env bash
# test-local-ai-shell.sh — Tests for shell/shellrc.d/25-local-ai.sh
set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — got '$got' want '$want'"
    FAIL=$((FAIL + 1))
  fi
}

assert_empty() {
  local label="$1" got="$2"
  if [[ -z "$got" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected empty, got '$got'"
    FAIL=$((FAIL + 1))
  fi
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAGMENT="$ROOT/shell/shellrc.d/25-local-ai.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME/.config/revealui" "$HOME/.local/bin"

# Static defaults (paths only)
cat >"$HOME/.config/revealui/local-ai.env" <<'EOF'
export REVEALUI_LOCAL_AI_TIER="${REVEALUI_LOCAL_AI_TIER:-idle}"
export OLLAMA_MODELS="${OLLAMA_MODELS:-/tmp/models/ollama}"
export LLM_PROVIDER="${LLM_PROVIDER:-}"
EOF

# Applied tier overrides
cat >"$HOME/.config/revealui/local-ai.active.env" <<'EOF'
export REVEALUI_LOCAL_AI_TIER=daily
export OLLAMA_MODELS=/mnt/studio/models/ollama
export LLM_PROVIDER=ollama
export LLM_MODEL=gemma3:1b
EOF

# Interactive shells: bash -i (noprofile/norc so we only load the fragment)
run_interactive() {
  # stderr noise from "no job control" is expected without a TTY
  bash --noprofile --norc -i -c "
    . \"$FRAGMENT\"
    $*
  " 2>/dev/null
}

run_noninteractive() {
  bash --noprofile --norc -c "
    . \"$FRAGMENT\"
    $*
  "
}

# 1) Interactive: active wins over static
out="$(run_interactive 'printf "%s\n" "$REVEALUI_LOCAL_AI_TIER"; printf "%s\n" "$OLLAMA_MODELS"; printf "%s\n" "$LLM_PROVIDER"; printf "%s\n" "${LLM_MODEL:-}"')"
tier="$(printf '%s\n' "$out" | sed -n '1p')"
models="$(printf '%s\n' "$out" | sed -n '2p')"
prov="$(printf '%s\n' "$out" | sed -n '3p')"
model="$(printf '%s\n' "$out" | sed -n '4p')"
assert_eq "interactive loads active tier" "$tier" "daily"
assert_eq "interactive OLLAMA_MODELS from active" "$models" "/mnt/studio/models/ollama"
assert_eq "interactive LLM_PROVIDER from active" "$prov" "ollama"
assert_eq "interactive LLM_MODEL from active" "$model" "gemma3:1b"

# 2) Non-interactive: skip by default
out2="$(run_noninteractive 'printf "%s\n" "${REVEALUI_LOCAL_AI_TIER:-}"')"
assert_empty "non-interactive skips without ALWAYS" "$out2"

# 3) Non-interactive with ALWAYS
out3="$(
  bash --noprofile --norc -c "
    export REVEALUI_LOCAL_AI_SHELL_ALWAYS=1
    . \"$FRAGMENT\"
    printf '%s\n' \"\${REVEALUI_LOCAL_AI_TIER:-}\"
  "
)"
assert_eq "ALWAYS loads in non-interactive" "$out3" "daily"

# 4) Opt-out
out4="$(
  bash --noprofile --norc -i -c "
    export REVEALUI_SKIP_LOCAL_AI_SHELL=1
    . \"$FRAGMENT\"
    printf '%s\n' \"\${REVEALUI_LOCAL_AI_TIER:-}\"
  " 2>/dev/null
)"
assert_empty "SKIP_LOCAL_AI_SHELL opt-out" "$out4"

# 5) Idle active unsets providers
cat >"$HOME/.config/revealui/local-ai.active.env" <<'EOF'
export REVEALUI_LOCAL_AI_TIER=idle
export OLLAMA_MODELS=/mnt/studio/models/ollama
unset LLM_PROVIDER
unset LLM_MODEL
unset INFERENCE_SNAPS_BASE_URL
EOF
out5="$(
  bash --noprofile --norc -i -c "
    export LLM_PROVIDER=should-be-cleared
    export LLM_MODEL=should-be-cleared
    . \"$FRAGMENT\"
    printf '%s\n' \"\${REVEALUI_LOCAL_AI_TIER:-}\"
    printf '%s\n' \"\${LLM_PROVIDER:-}\"
    printf '%s\n' \"\${LLM_MODEL:-}\"
  " 2>/dev/null
)"
t5="$(printf '%s\n' "$out5" | sed -n '1p')"
p5="$(printf '%s\n' "$out5" | sed -n '2p')"
m5="$(printf '%s\n' "$out5" | sed -n '3p')"
assert_eq "idle tier" "$t5" "idle"
assert_empty "idle unsets LLM_PROVIDER" "$p5"
assert_empty "idle unsets LLM_MODEL" "$m5"

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
