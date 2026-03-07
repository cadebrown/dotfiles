#!/usr/bin/env bash
# install/mise.sh - install mise and apply language runtime versions
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "mise"

### Install mise ###

if has mise; then
    log_ok "Already installed: $(mise --version)"
else
    log_info "Installing mise"
    ensure_dir "$HOME/.local/bin"
    run_logged bash <(curl -fsSL https://mise.run)
    # mise installs to ~/.local/bin — ensure it's on PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
    log_ok "Installed: $(mise --version)"
fi

### Activate for this session ###

eval "$(mise activate bash)"

### Install language runtimes ###

MISE_TOML="$PACKAGES_DIR/mise.toml"

if [[ ! -f "$MISE_TOML" ]]; then
    log_warn "No mise.toml found at $MISE_TOML — skipping runtime install"
    exit 0
fi

log_info "Installing runtimes from mise.toml"
run_logged mise install --yes --config "$MISE_TOML"
log_ok "Runtimes installed"
