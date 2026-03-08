#!/usr/bin/env bash
# install/claude.sh - install Claude Code plugins from packages/claude-plugins.txt
#
# The Claude Code CLI itself is installed via packages/npm.txt (install/npm.sh).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Claude Code plugins"

has claude || { log_warn "claude CLI not found — skipping plugins (run npm.sh first)"; exit 0; }

PLUGINS_TXT="$PACKAGES_DIR/claude-plugins.txt"
[[ -f "$PLUGINS_TXT" ]] || { log_warn "No claude-plugins.txt at $PLUGINS_TXT — skipping"; exit 0; }

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    plugin="${line%% *}"

    log_info "  $plugin"
    output=$(claude plugin install "$plugin" 2>&1) && status=0 || status=$?

    if [[ $status -eq 0 ]]; then
        log_ok "  installed $plugin"
        (( _ok++ )) || true
    elif echo "$output" | grep -qi "already installed\|already enabled"; then
        log_info "  skip  $plugin (already installed)"
        (( _skip++ )) || true
    else
        log_warn "  fail  $plugin: $output"
        (( _fail++ )) || true
    fi
done < "$PLUGINS_TXT"

log_ok "Claude plugins: ${_ok} installed, ${_skip} already present, ${_fail} failed"
