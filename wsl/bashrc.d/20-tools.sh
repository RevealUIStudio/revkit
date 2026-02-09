# Tool initialization: direnv, nvm, bun, go, pulumi, pip

# Zig / user bin
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"

# direnv
if command -v direnv &>/dev/null; then
    eval "$(direnv hook bash)"
    export DIRENV_LOG_FORMAT=""
    export DIRENV_WARN_TIMEOUT=""
fi

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# bun
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"

# go
[ -d "$HOME/go-install/go/bin" ] && export PATH="$PATH:$HOME/go-install/go/bin"

# pulumi
[ -d "$HOME/.pulumi/bin" ] && export PATH="$PATH:$HOME/.pulumi/bin"

# pip
export PIP_DEFAULT_TIMEOUT=300
export PIP_RETRIES=10

# local bin
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
