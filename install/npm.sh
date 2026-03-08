#!/usr/bin/env bash
# install/npm.sh - install global npm packages from packages/npm.txt
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "npm packages"

# Source nvm if npm isn't already on PATH (e.g. when npm.sh is run standalone)
if ! has npm; then
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" && nvm use default --silent 2>/dev/null || true
fi

has npm || { log_warn "npm not found — skipping"; exit 0; }

NPM_TXT="$PACKAGES_DIR/npm.txt"
[[ -f "$NPM_TXT" ]] || { log_warn "No npm.txt at $NPM_TXT — skipping"; exit 0; }

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    pkg="${line%% *}"

    if npm list -g "$pkg" --depth=0 &>/dev/null 2>&1; then
        log_ok "  $pkg (already installed)"
    else
        log_info "  installing $pkg"
        run_logged npm install -g "$pkg"
        log_ok "  $pkg installed"
    fi
done < "$NPM_TXT"
