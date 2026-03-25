# RevealUI DevKit

Portable WSL development environment toolkit for RevealUI projects.

## Quick Start

```bash
# 1. Copy a profile preset
cp profiles/solo-dev.toml config.toml

# 2. Edit your identity
$EDITOR config.toml

# 3. Render templates
./scripts/render.sh --config config.toml --output ~/.revealui

# 4. Source the environment
echo 'for f in ~/.revealui/wsl/bashrc.d/*.sh; do source "$f"; done' >> ~/.bashrc
```

## Profile Presets

| Profile | Tier | RAM | Cores | Docker | Studio Drive | Ollama |
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
revealui-devkit/
  templates/wsl/       # Parameterized templates ({{PLACEHOLDER}} tokens)
  profiles/            # Preset configurations per tier
  scripts/render.sh    # Template engine
  docs/                # Documentation
```

## License

MIT
