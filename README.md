# RevealUI DevKit

Portable WSL development environment toolkit for RevealUI projects.

## Quick Start

Clone this repo to your Windows home so WSL can reach it via `/mnt/c/`:

```powershell
# From PowerShell
cd $env:USERPROFILE
git clone https://github.com/RevealUIStudio/revkit.git .revealui
```

Then bootstrap from WSL:

```bash
bash /mnt/c/Users/$USER/.revealui/bootstrap-wsl.sh
```

The bootstrap installs helper scripts to `/usr/local/bin`, configures sudoers for passwordless drive mounting, adds a `~/.bashrc` hook that sources `wsl/bashrc.d/*.sh` from the cloned repo, links git and SSH configs via `include.path`, applies WSL boot optimization, initializes Sandbox drive directories (if `/mnt/sandbox` is mounted), deploys the M-4 sudoers/filesystem security scanner to `~/.claude/hooks/`, and wires the fleet-wide pre-push git hook via `git config --global core.hooksPath`.

Open a new WSL shell — you should see a `● RevealUI: managed` banner. Then `wsl --shutdown` from Windows to apply the boot optimization.

### Per-machine configuration (optional)

For parameterized configs (`.wslconfig`, `gitconfig`, `wsl.conf`, etc.) render a profile:

```bash
# 1. Pick a profile preset (see "Profile Presets" below)
cp profiles/solo-dev.toml config.toml

# 2. Edit identity / hardware values
$EDITOR config.toml

# 3. Render the parameterized configs
./scripts/render.sh --config config.toml --output ~/.revealui-render
```

Then copy or merge the rendered output into the canonical locations (e.g. `cp ~/.revealui-render/wsl/config/wsl.conf /etc/wsl.conf`).

## Profile Presets

| Profile | Tier | RAM | Cores | Docker | Sandbox Drive | Ollama |
|---------|------|-----|-------|--------|--------------|--------|
| `solo-dev.toml` | T0 | 8GB | 4 | No | No | No |
| `full-stack.toml` | T1 | 12GB | 8 | Yes | Yes | No |
| `ai-studio.toml` | T1+ | 16GB | 8 | Yes | Yes | Yes |
| `team.toml` | T1 | 16GB | 8 | Yes | Yes | No |

## Render Options

```bash
# Preview without writing
./scripts/render.sh --config config.toml --output ~/.revealui --dry-run

# Compare against existing setup
./scripts/render.sh --config config.toml --output /tmp/rendered --diff ~/.revealui

# Verbose output
./scripts/render.sh --config config.toml --output ~/.revealui --verbose
```

## Structure

```
revkit/
  bootstrap-wsl.sh     # Primary entry point (run once per WSL)
  bootstrap.ps1        # PowerShell-side prep
  wsl/                 # Source of truth — bashrc.d/, bin/, config/, docker/, setup-wsl-boot.sh
  templates/wsl/       # Parameterized templates ({{PLACEHOLDER}} tokens for .wslconfig, gitconfig, etc.)
  profiles/            # Preset TOML configs (per-tier resource + feature defaults)
  scripts/render.sh    # Template engine (renders templates/ → output dir using a profile)
  powershell/          # RevealUI.RevStation PowerShell module
  docs/                # Documentation
```

## License

MIT
