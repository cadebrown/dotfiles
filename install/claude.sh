#!/usr/bin/env sh
# install/claude.sh - install Claude Code plugins from claude-plugins.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "Claude Code plugins"

if ! has claude; then
    log_warn "claude CLI not found — skipping plugin install"
    exit 0
fi

PLUGINS_TXT="$(dirname "$SCRIPT_DIR")/packages/claude-plugins.txt"
if [ ! -f "$PLUGINS_TXT" ]; then
    log_warn "No claude-plugins.txt found at $PLUGINS_TXT"
    exit 0
fi

while IFS= read -r line; do
    case "$line" in
        ''|\#*) continue ;;
    esac
    plugin="${line%% *}"
    log_info "  claude plugin install $plugin"
    claude plugin install "$plugin" 2>&1 || log_warn "  failed (may already be installed)"
done < "$PLUGINS_TXT"

log_ok "Claude Code plugins installed"
