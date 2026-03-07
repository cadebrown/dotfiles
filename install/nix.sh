#!/usr/bin/env sh
# install/nix.sh - install Nix in user mode and apply home-manager config (Linux)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "Nix"

if [ "$OS" != "linux" ]; then
    log_warn "Skipping Nix — not on Linux (OS=$OS)"
    exit 0
fi

### Install Nix (user mode, no sudo) ###

if has nix; then
    log_ok "Nix already installed ($(nix --version))"
else
    log_info "Installing Nix in user mode (Determinate Systems installer)"
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
        | sh -s -- install --no-confirm

    # Source Nix into current shell
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    elif [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    fi
    log_ok "Nix installed: $(nix --version)"
fi

### Install home-manager ###

NIX_DIR="$(dirname "$SCRIPT_DIR")/packages/nix"

if ! has home-manager; then
    log_info "Installing home-manager"
    nix run nixpkgs#home-manager -- init
    # Add home-manager channel
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    nix-channel --update
    nix-shell '<home-manager>' -A install
    log_ok "home-manager installed"
else
    log_ok "home-manager already installed"
fi

### Apply home.nix ###

if [ -f "$NIX_DIR/flake.nix" ]; then
    log_info "Applying home-manager configuration via flake"
    home-manager switch --flake "$NIX_DIR#$(uname -m)-linux"
else
    log_info "Applying home-manager configuration"
    cp "$NIX_DIR/home.nix" ~/.config/home-manager/home.nix
    home-manager switch
fi

log_ok "Nix home-manager applied"
