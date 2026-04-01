# Antigravity / Chrome DevTools Bridge
# Forwards Chrome DevTools port from Windows host to WSL

WIN_IP=$(ip route show | grep -i default | awk '{ print $3}')

if [ -n "$WIN_IP" ] && ! pgrep -f "socat TCP-LISTEN:9222" > /dev/null 2>&1; then
    socat TCP-LISTEN:9222,fork,reuseaddr,bind=127.0.0.1 "TCP:$WIN_IP:9222" &>/dev/null &
fi

export XDG_RUNTIME_DIR="$HOME/.local/share/runtime"
