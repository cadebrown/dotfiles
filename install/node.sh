#!/usr/bin/env bash
# install/node.sh - install nvm and Node LTS
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Node (nvm)"

# NVM_DIR is set by _lib.sh to ~/.local/$PLAT/nvm

### Install nvm ###

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"
    log_ok "nvm already installed: $(nvm --version)"
else
    log_info "Installing nvm → $NVM_DIR"
    ensure_dir "$NVM_DIR"
    # Fetch the latest version tag from GitHub
    NVM_VERSION=$(curl -fsSL "https://api.github.com/repos/nvm-sh/nvm/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    log_info "Latest nvm: $NVM_VERSION"
    # PROFILE=/dev/null: prevent installer from appending to .zshrc/.bashrc
    # (chezmoi manages those files; nvm is sourced from dot_zprofile.tmpl)
    PROFILE=/dev/null run_logged bash <(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh")
    source "$NVM_DIR/nvm.sh"
    log_ok "nvm installed: $(nvm --version)"
fi

### Install Node LTS ###

if nvm ls --no-colors default 2>/dev/null | grep -q 'lts'; then
    log_ok "Node LTS already active: $(node --version)"
else
    log_info "Installing Node LTS"
    run_logged nvm install --lts
    run_logged nvm alias default 'lts/*'
    log_ok "Node installed: $(node --version)"
fi
