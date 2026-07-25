# shellcheck shell=bash
# Local AI host profile auto-load (WP3).
#
# Loads static paths/defaults, then the active tier profile written by
# InferenceService / Studio / revealui-local-ai. Does NOT start models.
#
# Order:
#   1. ~/.config/revealui/local-ai.env          (optional static defaults)
#   2. ~/.config/revealui/local-ai.active.env  (applied tier; overrides)
#
# Opt-out: REVEALUI_SKIP_LOCAL_AI_SHELL=1
# Non-interactive shells: skip unless REVEALUI_LOCAL_AI_SHELL_ALWAYS=1

if [ -n "${REVEALUI_SKIP_LOCAL_AI_SHELL:-}" ]; then
  return 0 2>/dev/null || true
fi

# Interactive by default; non-interactive only when forced (agents/scripts).
case $- in
  *i*) ;;
  *)
    if [ -z "${REVEALUI_LOCAL_AI_SHELL_ALWAYS:-}" ]; then
      return 0 2>/dev/null || true
    fi
    ;;
esac

_revealui_local_ai_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/revealui"
_revealui_local_ai_static="${REVEALUI_LOCAL_AI_ENV:-$_revealui_local_ai_cfg/local-ai.env}"
_revealui_local_ai_active="${REVEALUI_LOCAL_AI_ACTIVE_ENV:-$_revealui_local_ai_cfg/local-ai.active.env}"

if [ -f "$_revealui_local_ai_static" ]; then
  # shellcheck disable=SC1090
  . "$_revealui_local_ai_static"
fi

if [ -f "$_revealui_local_ai_active" ]; then
  # shellcheck disable=SC1090
  . "$_revealui_local_ai_active"
fi

# Ensure operator CLI is on PATH (thin wrapper → harnesses inference).
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi

unset _revealui_local_ai_cfg _revealui_local_ai_static _revealui_local_ai_active
