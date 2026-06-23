# shellcheck shell=bash
# Antigravity / Chrome DevTools Bridge
# Forwards the Windows host's Chrome DevTools port into WSL.
#
# WSL-ONLY: the default gateway is the Windows host only under WSL; on native
# Linux it is the LAN router (a socat to it would be wrong/harmful), and on
# macOS `ip` does not exist. So no-op entirely off WSL, keyed on the same
# /run/WSL marker lib/platform.sh uses.
[ -d "${REVKIT_WSL_RUN_DIR:-/run/WSL}" ] || return 0 2>/dev/null || exit 0

WIN_IP=$(ip route show | grep -i default | awk '{ print $3}')

if [ -n "$WIN_IP" ] && ! pgrep -f "socat TCP-LISTEN:9222" > /dev/null 2>&1; then
    socat TCP-LISTEN:9222,fork,reuseaddr,bind=127.0.0.1 "TCP:$WIN_IP:9222" &>/dev/null &
fi
