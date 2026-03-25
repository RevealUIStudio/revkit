#!/usr/bin/env bash
# render.sh — Template engine for revealui-devkit
#
# Reads a TOML config file, walks templates/ recursively, replaces
# {{PLACEHOLDER}} patterns with config values, writes rendered files
# to an output directory.
#
# Usage:
#   render.sh --config config.toml --output /tmp/rendered
#   render.sh --config config.toml --output /tmp/rendered --dry-run
#   render.sh --config config.toml --output /tmp/rendered --diff /existing/dir
#   render.sh --config config.toml --output /tmp/rendered --templates ./templates
#
# Requires: bash 4+, sed, grep, diff (for --diff mode)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly DEFAULT_TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/templates"

# Ordered list of known placeholders and their TOML key + section mappings.
# Format: PLACEHOLDER_NAME=section.key
declare -A PLACEHOLDER_MAP=(
  [USERNAME]="identity.username"
  [WINDOWS_USER]="identity.windows_user"
  [GIT_NAME]="identity.git_name"
  [GIT_EMAIL]="identity.git_email"
  [GITHUB_ORG]="identity.github_org"
  [WSL_MEMORY]="hardware.wsl_memory"
  [WSL_PROCESSORS]="hardware.wsl_processors"
  [WSL_SWAP]="hardware.wsl_swap"
  [STUDIO_MOUNT]="infrastructure.studio_mount"
  [POSTGRES_PORT]="infrastructure.postgres_port"
  [REDIS_PORT]="infrastructure.redis_port"
  [OLLAMA_PORT]="infrastructure.ollama_port"
  [CHROME_DEVTOOLS_PORT]="infrastructure.chrome_devtools_port"
  [PROJECT_DIR]="project.project_dir"
  [PROJECT_NAME]="project.project_name"
)

# Feature flags (parsed separately, not substituted as placeholders)
declare -A FEATURES=()

# Resolved placeholder values
declare -A VALUES=()

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_log()    { printf '%s\n' "$*" >&2; }
_info()   { _log "[info]  $*"; }
_warn()   { _log "[warn]  $*"; }
_error()  { _log "[error] $*"; }
_die()    { _error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------

usage() {
  cat <<'HELPTEXT'
render.sh — RevealUI DevKit template renderer

USAGE
  render.sh --config <file> --output <dir> [OPTIONS]

REQUIRED
  --config  <file>    Path to TOML configuration file
  --output  <dir>     Directory to write rendered files into

OPTIONS
  --templates <dir>   Template source directory (default: ../templates relative to script)
  --dry-run           Print what would be rendered without writing files
  --diff <dir>        Show diff between rendered output and an existing directory
  --verbose           Print each file as it is processed
  --help              Show this help text
  --version           Print version and exit

SUPPORTED PLACEHOLDERS (from config TOML)
  {{USERNAME}}             identity.username
  {{WINDOWS_USER}}         identity.windows_user
  {{GIT_NAME}}             identity.git_name
  {{GIT_EMAIL}}            identity.git_email
  {{GITHUB_ORG}}           identity.github_org
  {{WSL_MEMORY}}           hardware.wsl_memory
  {{WSL_PROCESSORS}}       hardware.wsl_processors
  {{WSL_SWAP}}             hardware.wsl_swap
  {{STUDIO_MOUNT}}         infrastructure.studio_mount
  {{POSTGRES_PORT}}        infrastructure.postgres_port
  {{REDIS_PORT}}           infrastructure.redis_port
  {{OLLAMA_PORT}}          infrastructure.ollama_port
  {{CHROME_DEVTOOLS_PORT}} infrastructure.chrome_devtools_port
  {{PROJECT_DIR}}          project.project_dir
  {{PROJECT_NAME}}         project.project_name

CONFIG TOML SECTIONS
  [identity]        User and git identity
  [hardware]        WSL resource limits
  [infrastructure]  Ports and mount points
  [features]        Boolean feature flags (docker, nix, revvault, tailscale, ollama)
  [project]         Project paths and name

EXAMPLES
  # Render templates to /tmp/devkit-output
  render.sh --config profiles/default.toml --output /tmp/devkit-output

  # Preview without writing
  render.sh --config profiles/default.toml --output /tmp/devkit-output --dry-run

  # Compare rendered output against live system
  render.sh --config profiles/default.toml --output /tmp/devkit-output --diff /home/user
HELPTEXT
}

# ---------------------------------------------------------------------------
# TOML parser (basic, section-aware, no external tools)
# ---------------------------------------------------------------------------

# parse_toml <file>
#
# Reads a TOML file and populates VALUES and FEATURES associative arrays.
# Handles: [section] headers, key = "value" (quoted), key = value (unquoted),
# key = true/false (booleans for features), blank lines, and # comments.
parse_toml() {
  local file="$1"
  local current_section=""
  local line key value section_key

  [[ -f "$file" ]] || _die "Config file not found: $file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip inline comments (only outside quoted values)
    # Strip leading/trailing whitespace
    line="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<< "$line")"

    # Skip blank lines and full-line comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Section header: [section_name]
    if [[ "$line" =~ ^\[([a-zA-Z_][a-zA-Z0-9_]*)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    # Key-value pair: key = value
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\ *=\ *(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Strip surrounding quotes (single or double)
      value="$(sed 's/^["'\'']\(.*\)["'\''"]$/\1/' <<< "$value")"

      # Strip any trailing inline comment from unquoted values
      value="$(sed 's/[[:space:]]*#.*$//' <<< "$value")"

      section_key="${current_section}.${key}"

      # Feature flags go into FEATURES array
      if [[ "$current_section" == "features" ]]; then
        FEATURES["$key"]="$value"
        continue
      fi

      # Map section.key to placeholder name and store the value
      local placeholder
      for placeholder in "${!PLACEHOLDER_MAP[@]}"; do
        if [[ "${PLACEHOLDER_MAP[$placeholder]}" == "$section_key" ]]; then
          VALUES["$placeholder"]="$value"
          break
        fi
      done

      continue
    fi
  done < "$file"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validate_config() {
  local missing=()
  local placeholder

  for placeholder in "${!PLACEHOLDER_MAP[@]}"; do
    if [[ -z "${VALUES[$placeholder]+set}" ]]; then
      missing+=("{{${placeholder}}} (${PLACEHOLDER_MAP[$placeholder]})")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    _warn "Missing config values for placeholders:"
    for m in "${missing[@]}"; do
      _warn "  - $m"
    done
    _warn "Templates referencing these placeholders will retain raw {{...}} markers."
  fi
}

# ---------------------------------------------------------------------------
# Template rendering
# ---------------------------------------------------------------------------

# render_string <string>
#
# Replaces all {{PLACEHOLDER}} patterns in the input string with resolved values.
# Uses iterative sed to avoid pipe chains.
render_string() {
  local content="$1"
  local placeholder value

  for placeholder in "${!VALUES[@]}"; do
    value="${VALUES[$placeholder]}"
    # Escape sed special characters in the replacement value (delimiter is |)
    value="${value//\\/\\\\}"  # escape backslashes first
    value="${value//&/\\&}"    # escape ampersand
    value="${value//|/\\|}"    # escape pipe (our delimiter)
    content="$(sed "s|{{${placeholder}}}|${value}|g" <<< "$content")"
  done

  printf '%s' "$content"
}

# render_file <source_file> <dest_file>
#
# Reads source, renders placeholders, writes to dest (or prints in dry-run).
render_file() {
  local src="$1"
  local dest="$2"
  local content rendered

  content="$(cat "$src")"
  rendered="$(render_string "$content")"

  if [[ "$DRY_RUN" == "true" ]]; then
    _info "[dry-run] Would render: $src -> $dest"
    # Check for unresolved placeholders
    local unresolved
    unresolved="$(grep -oE '\{\{[A-Z_]+\}\}' <<< "$rendered" 2>/dev/null || true)"
    if [[ -n "$unresolved" ]]; then
      _warn "  Unresolved placeholders: $(tr '\n' ' ' <<< "$unresolved")"
    fi
    return 0
  fi

  # Create parent directory
  mkdir -p "$(dirname "$dest")"

  # Write rendered content (atomic: write to tmp then move)
  local tmp_dest="${dest}.tmp.$$"
  printf '%s' "$rendered" > "$tmp_dest"

  # Preserve source file permissions
  chmod --reference="$src" "$tmp_dest" 2>/dev/null || true

  mv -f "$tmp_dest" "$dest"

  [[ "$VERBOSE" == "true" ]] && _info "Rendered: $src -> $dest"
}

# ---------------------------------------------------------------------------
# Directory walking
# ---------------------------------------------------------------------------

# walk_templates <template_dir> <output_dir>
#
# Recursively finds all files in template_dir, renders each, writes to
# the corresponding path under output_dir.
walk_templates() {
  local tmpl_dir="$1"
  local out_dir="$2"
  local file_count=0
  local skip_count=0

  # Verify template directory is not empty
  if [[ -z "$(find "$tmpl_dir" -type f 2>/dev/null | head -1)" ]]; then
    _warn "No template files found in: $tmpl_dir"
    return 0
  fi

  while IFS= read -r -d '' src_file; do
    # Compute relative path from template root
    local rel_path="${src_file#"${tmpl_dir}"/}"
    local dest_file="${out_dir}/${rel_path}"

    # Render the relative path itself (directory names may contain placeholders)
    dest_file="$(render_string "$dest_file")"

    render_file "$src_file" "$dest_file"
    file_count=$((file_count + 1))
  done < <(find "$tmpl_dir" -type f -print0 | sort -z)

  if [[ "$DRY_RUN" == "true" ]]; then
    _info "[dry-run] Total files that would be rendered: $file_count"
  else
    _info "Rendered $file_count file(s) to: $out_dir"
  fi
}

# ---------------------------------------------------------------------------
# Diff mode
# ---------------------------------------------------------------------------

# diff_output <rendered_dir> <compare_dir>
#
# Compares rendered output against an existing directory, showing differences.
diff_output() {
  local rendered_dir="$1"
  local compare_dir="$2"
  local has_diff=0

  [[ -d "$compare_dir" ]] || _die "Diff target directory not found: $compare_dir"

  _info "Comparing rendered output against: $compare_dir"
  _info "---"

  while IFS= read -r -d '' rendered_file; do
    local rel_path="${rendered_file#"${rendered_dir}"/}"
    local compare_file="${compare_dir}/${rel_path}"

    if [[ ! -f "$compare_file" ]]; then
      printf '\e[32m+ New file: %s\e[0m\n' "$rel_path"
      has_diff=1
      continue
    fi

    local file_diff
    file_diff="$(diff -u "$compare_file" "$rendered_file" 2>/dev/null || true)"
    if [[ -n "$file_diff" ]]; then
      printf '\e[33m~ Modified: %s\e[0m\n' "$rel_path"
      printf '%s\n\n' "$file_diff"
      has_diff=1
    fi
  done < <(find "$rendered_dir" -type f -print0 | sort -z)

  # Check for files in compare_dir that are not in rendered output
  # (only within the template subtree — we don't flag unrelated files)
  while IFS= read -r -d '' compare_file; do
    local rel_path="${compare_file#"${compare_dir}"/}"
    local rendered_file="${rendered_dir}/${rel_path}"

    if [[ ! -f "$rendered_file" ]]; then
      printf '\e[31m- Not in templates: %s\e[0m\n' "$rel_path"
      has_diff=1
    fi
  done < <(find "$compare_dir" -type f -print0 | sort -z)

  if [[ "$has_diff" -eq 0 ]]; then
    _info "No differences found."
  fi

  return "$has_diff"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CONFIG_FILE=""
OUTPUT_DIR=""
TEMPLATE_DIR="$DEFAULT_TEMPLATE_DIR"
DRY_RUN="false"
DIFF_DIR=""
VERBOSE="false"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ -n "${2:-}" ]] || _die "--config requires a file path"
        CONFIG_FILE="$2"
        shift 2
        ;;
      --output)
        [[ -n "${2:-}" ]] || _die "--output requires a directory path"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --templates)
        [[ -n "${2:-}" ]] || _die "--templates requires a directory path"
        TEMPLATE_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --diff)
        [[ -n "${2:-}" ]] || _die "--diff requires a directory path"
        DIFF_DIR="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE="true"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --version)
        printf '%s v%s\n' "$SCRIPT_NAME" "$VERSION"
        exit 0
        ;;
      -*)
        _die "Unknown option: $1 (use --help for usage)"
        ;;
      *)
        _die "Unexpected argument: $1 (use --help for usage)"
        ;;
    esac
  done
}

validate_args() {
  [[ -n "$CONFIG_FILE" ]] || _die "Missing required --config <file> (use --help for usage)"
  [[ -n "$OUTPUT_DIR" ]]  || _die "Missing required --output <dir> (use --help for usage)"
  [[ -f "$CONFIG_FILE" ]] || _die "Config file not found: $CONFIG_FILE"
  [[ -d "$TEMPLATE_DIR" ]] || _die "Template directory not found: $TEMPLATE_DIR"

  # Resolve to absolute paths
  CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
  TEMPLATE_DIR="$(cd "$TEMPLATE_DIR" && pwd)"

  if [[ -n "$DIFF_DIR" ]]; then
    [[ -d "$DIFF_DIR" ]] || _die "Diff directory not found: $DIFF_DIR"
    DIFF_DIR="$(cd "$DIFF_DIR" && pwd)"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"
  validate_args

  _info "Config:    $CONFIG_FILE"
  _info "Templates: $TEMPLATE_DIR"
  _info "Output:    $OUTPUT_DIR"
  [[ "$DRY_RUN" == "true" ]] && _info "Mode:      dry-run"
  [[ -n "$DIFF_DIR" ]]       && _info "Diff:      $DIFF_DIR"
  _info "---"

  # Parse config
  parse_toml "$CONFIG_FILE"
  validate_config

  # Log resolved values in verbose mode
  if [[ "$VERBOSE" == "true" ]]; then
    _info "Resolved placeholders:"
    for placeholder in $(printf '%s\n' "${!VALUES[@]}" | sort); do
      _info "  {{${placeholder}}} = ${VALUES[$placeholder]}"
    done
    if [[ ${#FEATURES[@]} -gt 0 ]]; then
      _info "Feature flags:"
      for feat in $(printf '%s\n' "${!FEATURES[@]}" | sort); do
        _info "  ${feat} = ${FEATURES[$feat]}"
      done
    fi
    _info "---"
  fi

  # Create output directory (unless dry-run)
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$OUTPUT_DIR"
  fi

  # Render templates
  walk_templates "$TEMPLATE_DIR" "$OUTPUT_DIR"

  # Diff mode: render first, then compare
  if [[ -n "$DIFF_DIR" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      _warn "--diff is ignored in dry-run mode (no rendered files to compare)"
    else
      _info "---"
      diff_output "$OUTPUT_DIR" "$DIFF_DIR" || true
    fi
  fi

  _info "Done."
}

main "$@"
