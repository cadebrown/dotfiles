#!/usr/bin/env bash
# install/node.sh - install Node.js v25 via nvm
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Node.js (nvm)"

# nvm goes under LOCAL_PLAT so each arch+OS gets its own node binaries
# (nvm itself is shell scripts, but the node versions it installs are arch-specific)

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log_ok "nvm already installed: $NVM_DIR"
else
    log_info "Installing nvm..."
    ensure_dir "$NVM_DIR"
    # PROFILE=/dev/null: don't touch shell configs (chezmoi manages those)
    _nvm_script="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh -o "$_nvm_script"
    NVM_DIR="$NVM_DIR" PROFILE=/dev/null bash "$_nvm_script" 2>&1 | sed 's/^/    /'
    rm -f "$_nvm_script"
fi

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

if nvm ls 25 2>/dev/null | grep -qE 'v25\.'; then
    log_ok "Node v25 already installed"
else
    log_info "Installing Node.js v25..."
    nvm install 25 2>&1 | sed 's/^/    /'
fi

nvm alias default 25
nvm use default --silent

log_ok "Node.js: $(node --version)"
log_ok "npm:     $(npm --version)"
