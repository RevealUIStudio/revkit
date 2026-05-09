# shellcheck shell=bash
# Tool initialization: direnv, fnm/nvm, bun, rust, go, pulumi, pip

# Zig / user bin
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"

# direnv
if command -v direnv &>/dev/null; then
    eval "$(direnv hook bash)"
    export DIRENV_LOG_FORMAT=""
    export DIRENV_WARN_TIMEOUT=""
fi

# fnm (preferred) / nvm (fallback)
if command -v fnm &>/dev/null; then
    eval "$(fnm env)"
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
fi

# bun
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"

# rust / cargo (must precede 60-license.sh which calls `command -v revvault`)
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

# go
[ -d "$HOME/go-install/go/bin" ] && export PATH="$PATH:$HOME/go-install/go/bin"

# pulumi
[ -d "$HOME/.pulumi/bin" ] && export PATH="$PATH:$HOME/.pulumi/bin"

# pip
export PIP_DEFAULT_TIMEOUT=300
export PIP_RETRIES=10

# local bin
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
