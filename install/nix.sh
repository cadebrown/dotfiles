#!/usr/bin/env bash
# install/nix.sh - install Nix (user mode) and apply home-manager config (Linux)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Nix"

[[ "$OS" == "linux" ]] || { log_warn "Not on Linux — skipping"; exit 0; }

NIX_DIR="$PACKAGES_DIR/nix"

### Install Nix ###

if has nix; then
    log_ok "Nix already installed: $(nix --version)"
else
    log_info "Installing Nix (Determinate Systems installer)"
    run_logged bash <(curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix) \
        install --no-confirm

    # Source Nix into the current session
    if [[ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]]; then
        # shellcheck disable=SC1091
        source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    elif [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi

    log_ok "Nix installed: $(nix --version)"
fi

### Install home-manager ###

if has home-manager; then
    log_ok "home-manager already installed: $(home-manager --version)"
else
    log_info "Installing home-manager"
    # Standalone installation via flake (no channels needed)
    run_logged nix run home-manager/master -- init
    log_ok "home-manager installed"
fi

### Apply configuration ###

log_info "Applying home-manager configuration"

if [[ -f "$NIX_DIR/flake.nix" ]]; then
    ensure_dir "$HOME/.config/home-manager"
    # Link our flake into the home-manager config location
    ln -sf "$NIX_DIR/flake.nix" "$HOME/.config/home-manager/flake.nix"
    ln -sf "$NIX_DIR/home.nix"  "$HOME/.config/home-manager/home.nix"
    run_logged home-manager switch --flake "$HOME/.config/home-manager"
else
    ensure_dir "$HOME/.config/home-manager"
    cp "$NIX_DIR/home.nix" "$HOME/.config/home-manager/home.nix"
    run_logged home-manager switch
fi

log_ok "home-manager configuration applied"
