#!/usr/bin/env bash
# install/homebrew.sh - install Homebrew and apply Brewfile (macOS only)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Homebrew"

[[ "$OS" == "darwin" ]] || { log_warn "Not on macOS — skipping"; exit 0; }

### Install Homebrew ###

if has brew; then
    log_ok "Already installed: $(brew --version | head -1)"
else
    log_info "Installing Homebrew"
    run_logged bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH for this session (needed right after install)
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

### Apply Brewfile ###

BREWFILE="$PACKAGES_DIR/Brewfile"
[[ -f "$BREWFILE" ]] || die "Brewfile not found at $BREWFILE"

log_info "Updating Homebrew"
run_logged brew update

log_info "Upgrading installed packages"
run_logged brew upgrade

log_info "Applying Brewfile (installs anything new)"
run_logged brew bundle install --file="$BREWFILE"

log_ok "Homebrew packages up to date"
