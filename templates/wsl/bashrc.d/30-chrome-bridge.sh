# shellcheck shell=bash disable=SC1083
# Chrome DevTools Bridge — forwards from Windows host to WSL
# (SC1083 disabled — file contains {{...}} template placeholders that
# render.sh substitutes; ShellCheck reads them as literal braces.)
WIN_IP=$(ip route show | grep -i default | awk '{ print $3}')
if [ -n "$WIN_IP" ] && ! pgrep -f "socat TCP-LISTEN:{{CHROME_DEVTOOLS_PORT}}" > /dev/null 2>&1; then
    socat TCP-LISTEN:{{CHROME_DEVTOOLS_PORT}},fork,reuseaddr,bind=127.0.0.1 "TCP:$WIN_IP:{{CHROME_DEVTOOLS_PORT}}" &>/dev/null &
fi
export XDG_RUNTIME_DIR="$HOME/.local/share/runtime"
