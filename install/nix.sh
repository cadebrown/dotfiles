#!/usr/bin/env bash
# install/nix.sh - install Nix + home-manager and apply home.nix (macOS + Linux)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Nix"

NIX_DIR="$PACKAGES_DIR/nix"

# Map our ARCH/OS to Nix system string (e.g. aarch64-darwin, x86_64-linux)
NIX_SYSTEM="$ARCH-$OS"

### Install Nix ###

if has nix; then
    log_ok "Nix already installed: $(nix --version)"
else
    log_info "Installing Nix (Determinate Systems installer) for $NIX_SYSTEM"
    run_logged bash <(curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix) \
        install --no-confirm

    # Source Nix into the current session (daemon profile takes priority)
    if [[ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]]; then
        # shellcheck disable=SC1091
        source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    elif [[ -e "$NIX_PROFILE/etc/profile.d/nix.sh" ]]; then
        # shellcheck disable=SC1091
        source "$NIX_PROFILE/etc/profile.d/nix.sh"
    fi

    log_ok "Nix installed: $(nix --version)"
fi

### Install home-manager ###

if has home-manager; then
    log_ok "home-manager already installed: $(home-manager --version)"
else
    log_info "Installing home-manager"
    # Install standalone via flake — no channels needed
    run_logged nix run home-manager/master -- init
    log_ok "home-manager installed"
fi

### Apply configuration ###

log_info "Applying home-manager for $NIX_SYSTEM"

ensure_dir "$HOME/.config/home-manager"
# Link our flake into the home-manager config dir so `home-manager switch`
# and `home-manager generations` work without --flake each time
ln -sf "$NIX_DIR/flake.nix" "$HOME/.config/home-manager/flake.nix"
ln -sf "$NIX_DIR/home.nix"  "$HOME/.config/home-manager/home.nix"

# Switch to the config for the current system
run_logged home-manager switch --flake "$HOME/.config/home-manager#$NIX_SYSTEM"

log_ok "home-manager configuration applied"
