#!/usr/bin/env bash
# install/auth.sh - interactive guided API token setup
#
# Creates ~/.{service}.env files with API tokens. Each file is chmod 600.
# Called by bootstrap with DF_DO_AUTH=1, or run directly:
#   bash ~/dotfiles/install/auth.sh
#
# Env files are sourced by _lib.sh on every install script run, making
# tokens available to cargo-binstall (GITHUB_TOKEN), Claude Code
# (ANTHROPIC_API_KEY), Codex CLI (OPENAI_API_KEY), etc.
#
# Safe to re-run: skips credentials that are already set.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "API token setup"

# _setup_token ENV_FILE VAR_NAME DESCRIPTION INSTRUCTIONS
_setup_token() {
    local env_file="$1" var_name="$2" description="$3" instructions="$4"

    # Check if already set (either in env or in the file)
    if [[ -f "$env_file" ]] && grep -q "^export ${var_name}=" "$env_file" 2>/dev/null; then
        log_okay "$var_name already configured"
        return 0
    fi

    echo ""
    log_info "$description"
    printf "${_DIM}%s${_RESET}\n" "$instructions"
    echo ""

    read -rp "  $var_name (Enter to skip): " _value

    if [[ -z "$_value" ]]; then
        log_info "Skipped $var_name"
        return 0
    fi

    # Append to env file
    echo "export ${var_name}=\"${_value}\"" >> "$env_file"
    chmod 600 "$env_file"
    log_okay "$var_name → $env_file"
}

### GitHub ###

_setup_token "$HOME/.github.env" "GITHUB_TOKEN" \
    "GitHub personal access token" \
    "  Used by: cargo-binstall, gh CLI, Homebrew (rate limits)
  Create at: https://github.com/settings/tokens
  Scopes: repo (private repos) or fine-grained with no permissions (rate limit only)"

### Anthropic ###

_setup_token "$HOME/.anthropic.env" "ANTHROPIC_API_KEY" \
    "Anthropic API key" \
    "  Used by: Claude Code CLI
  Create at: https://console.anthropic.com/settings/keys"

### OpenAI ###

_setup_token "$HOME/.openai.env" "OPENAI_API_KEY" \
    "OpenAI API key" \
    "  Used by: Codex CLI
  Create at: https://platform.openai.com/api-keys"

echo ""
log_okay "Auth setup complete"
log_info "Env files are sourced automatically by install scripts via _lib.sh"
