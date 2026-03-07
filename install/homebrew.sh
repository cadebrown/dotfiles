#!/usr/bin/env sh
# install/homebrew.sh - install Homebrew and apply Brewfile (macOS only)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "Homebrew"

if [ "$OS" != "darwin" ]; then
    log_warn "Skipping Homebrew — not on macOS (OS=$OS)"
    exit 0
fi

if ! has brew; then
    log_info "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    log_ok "Homebrew already installed ($(brew --version | head -1))"
fi

# Reload brew into PATH (needed when we just installed it)
if [ -e "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -e "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

BREWFILE="$(dirname "$SCRIPT_DIR")/packages/Brewfile"
if [ ! -f "$BREWFILE" ]; then
    log_error "Brewfile not found at $BREWFILE"
    exit 1
fi

log_info "Running brew bundle (this may take a while)"
brew bundle install --file="$BREWFILE" --no-lock
log_ok "Homebrew packages installed"
