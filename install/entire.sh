#!/usr/bin/env bash
# Enable Entire checkpoints for this dotfiles repository only.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Entire repository checkpoints"

has entire || { log_warn "entire not found — install the Brew/Go package first; skipping"; exit 0; }
has jq || { log_warn "jq not found — cannot reconcile Entire agents; skipping"; exit 0; }

cd "$DF_ROOT"

_status="$(entire status --json 2>/dev/null || printf '{"enabled":false,"agents":[]}')"
if ! jq -e '.enabled == true' >/dev/null <<<"$_status"; then
    entire enable --project --agent codex --skip-push-sessions \
        --telemetry=false --no-init-repo -y
    _status="$(entire status --json)"
fi

_ensure_agent() {
    local _cli_name="$1" _display_name="$2"
    if jq -e --arg name "$_display_name" '(.agents // []) | index($name) != null' \
        >/dev/null <<<"$_status"; then
        log_info "  skip  $_display_name (already configured)"
        return 0
    fi
    entire agent add "$_cli_name"
    _status="$(entire status --json)"
}

_ensure_agent codex "Codex"
_ensure_agent claude-code "Claude Code"
_ensure_agent opencode "OpenCode"
_ensure_agent pi "Pi"

# Entire's Codex hooks are project-local and require content-hash trust. Reuse
# the managed Codex sync so only this repository's exact hook path is trusted.
if has codex; then
    bash "$DF_ROOT/install/codex.sh" sync-config
fi

log_okay "Entire enabled for $DF_ROOT only"
