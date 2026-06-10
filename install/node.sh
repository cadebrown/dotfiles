#!/usr/bin/env bash
# install/node.sh - install Node.js v25 via nvm
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Node.js (nvm)"

# nvm goes under LOCAL_PLAT so each arch+OS gets its own node binaries
# (nvm itself is shell scripts, but the node versions it installs are arch-specific)

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log_okay "nvm already installed: $NVM_DIR"
else
    log_info "Installing nvm..."
    ensure_dir "$NVM_DIR"
    # PROFILE=/dev/null: don't touch shell configs (chezmoi manages those)
    _nvm_script="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh -o "$_nvm_script"
    NVM_DIR="$NVM_DIR" PROFILE=/dev/null run_logged bash "$_nvm_script"
    rm -f "$_nvm_script"
fi

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

if nvm ls 25 2>/dev/null | grep -qE 'v25\.'; then
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        log_info "Upgrading Node.js v25 to latest 25.x..."
        run_logged nvm install 25 --reinstall-packages-from=25 --latest-npm
    else
        log_okay "Node v25 already installed"
    fi
else
    log_info "Installing Node.js v25..."
    run_logged nvm install 25
fi

nvm alias default 25
nvm use default --silent

log_okay "Node.js: $(node --version)"
log_okay "npm:     $(npm --version)"

### npm global packages ###

NPM_TXT="$DF_PACKAGES/npm.txt"
if [[ ! -f "$NPM_TXT" ]]; then
    log_warn "No npm.txt at $NPM_TXT — skipping npm packages"
    exit 0
fi

_pkg_count=0
_upgrade_count=0
while IFS= read -r pkg; do
    # Entries may pin a version ("<name>@1.2.3", scoped names keep their
    # leading @). Split at the LAST @ — a tail with "/" in it is the package
    # path of a scoped name, not a version.
    _name="$pkg" _pin="" _tail="${pkg##*@}"
    if [[ "$pkg" == *"@"* && -n "$_tail" && "$_tail" != *"/"* && "$pkg" != "@$_tail" ]]; then
        _name="${pkg%@*}"
        _pin="$_tail"
    fi

    if [[ -n "$_pin" ]]; then
        # Pinned: hold this exact version; upgrade mode does not move it.
        if npm list -g "${_name}@${_pin}" --depth=0 &>/dev/null; then
            log_okay "  $_name@$_pin (pinned, installed)"
        else
            log_info "  installing $_name@$_pin (pinned)"
            run_logged npm install -g "${_name}@${_pin}"
            log_okay "  $_name@$_pin"
            (( _pkg_count++ )) || true
        fi
    elif npm list -g "$_name" --depth=0 &>/dev/null; then
        if [[ "${DF_MODE:-}" == "upgrade" ]]; then
            log_info "  upgrading $_name"
            run_logged npm install -g "$_name@latest"
            log_okay "  $_name (upgraded)"
            (( _upgrade_count++ )) || true
        else
            log_okay "  $_name (already installed)"
        fi
    else
        log_info "  installing $_name"
        run_logged npm install -g "$_name"
        log_okay "  $_name"
        (( _pkg_count++ )) || true
    fi
done < <(_read_package_list "$NPM_TXT")

if [[ $_pkg_count -eq 0 && $_upgrade_count -eq 0 ]]; then
    log_info "All npm packages already installed"
fi
