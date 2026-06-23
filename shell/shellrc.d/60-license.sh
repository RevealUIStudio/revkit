# shellcheck shell=bash
# RevealUI Studio founder license key (sourced from revvault per the secrets hardline rule)
#
# Path: revealui/dev/founder-license-key
# Format: RVUI-<tier>-<32 hex chars>
# Consumer: revdev daemon — see ~/revfleet/revdev/packages/daemon/src/license.ts
#
# Failure mode (per ADR docs/decisions/2026-05-01-license-key-revvault.md): quiet with warning.
# If revvault is unavailable or returns empty, REVEALUI_LICENSE_KEY stays unset
# (so consuming code fails loudly per the secrets rule), and a one-line warning
# explains why on stderr. No shell-init breakage.

if command -v revvault >/dev/null 2>&1; then
  _key="$(revvault get revealui/dev/founder-license-key 2>/dev/null)"
  if [ -n "$_key" ]; then
    export REVEALUI_LICENSE_KEY="$_key"
  else
    echo "warning: revvault get revealui/dev/founder-license-key returned empty (REVEALUI_LICENSE_KEY unset)" >&2
  fi
  unset _key
else
  echo "warning: revvault not in PATH (REVEALUI_LICENSE_KEY unset)" >&2
fi
