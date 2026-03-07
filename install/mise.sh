#!/usr/bin/env bash
# install/mise.sh - install mise and apply language runtime versions
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "mise"

MISE_BIN="$HOME/.local/bin/mise"

if has mise || [ -x "$MISE_BIN" ]; then
    MISE_CMD="$(has mise && echo mise || echo "$MISE_BIN")"
    log_ok "mise already installed ($($MISE_CMD --version))"
else
    log_info "Installing mise"
    ensure_dir "$HOME/.local/bin"
    curl https://mise.run | sh
    log_ok "mise installed"
fi

MISE_CMD="$(has mise && echo mise || echo "$MISE_BIN")"

# Activate for current session
eval "$($MISE_CMD activate sh)"

MISE_TOML="$(dirname "$SCRIPT_DIR")/packages/mise.toml"
if [ -f "$MISE_TOML" ]; then
    log_info "Installing language runtimes from $MISE_TOML"
    "$MISE_CMD" install --yes --config "$MISE_TOML"
    log_ok "mise runtimes installed"
else
    log_warn "No mise.toml found at $MISE_TOML, skipping runtime install"
fi
