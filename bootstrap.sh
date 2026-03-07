#!/usr/bin/env bash
# bootstrap.sh - set up a new machine from scratch
#
# Usage (one-liner, no repo needed):
#   curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
#
# Usage (from cloned repo):
#   git clone https://github.com/cadebrown/dotfiles ~/dotfiles
#   ~/dotfiles/bootstrap.sh
#
# Environment variables:
#   GITHUB_REPO      — override the source repo (default: cadebrown/dotfiles)
#   INSTALL_RUST     — set to 0 to skip Rust install
#   INSTALL_PYTHON   — set to 0 to skip Python install
#   INSTALL_CLAUDE   — set to 0 to skip Claude plugin install

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-cadebrown/dotfiles}"

# Source _lib.sh — works both from repo and via curl | bash
_LIB="$(dirname "${BASH_SOURCE[0]}")/install/_lib.sh"
if [[ -f "$_LIB" ]]; then
    # shellcheck source=install/_lib.sh
    source "$_LIB"
else
    # Running via curl | bash — fetch _lib.sh temporarily
    _TMP_LIB="$(mktemp)"
    trap 'rm -f "$_TMP_LIB"' EXIT
    curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/install/_lib.sh" -o "$_TMP_LIB"
    source "$_TMP_LIB"
fi

INSTALL_DIR="$DOTFILES_ROOT/install"

log_section "dotfiles bootstrap"
log_info "OS: $OS | Arch: $ARCH | Host: $(hostname)"

### 1. chezmoi ###

log_section "1 — chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"
ensure_dir "$ARCH_BIN"

if has chezmoi; then
    CHEZMOI_BIN="$(command -v chezmoi)"
    log_ok "chezmoi already available: $(chezmoi --version)"
elif [[ -x "$CHEZMOI_BIN" ]]; then
    log_ok "chezmoi already installed: $("$CHEZMOI_BIN" --version)"
else
    log_info "Installing chezmoi → $ARCH_BIN"
    run_logged bash "$INSTALL_DIR/chezmoi.sh"
fi

### 2. dotfiles ###

log_section "2 — dotfiles (chezmoi apply)"

# If we're running from inside the repo, use it as the source directly
_REPO_HOME="$(dirname "${BASH_SOURCE[0]}")/home"
if [[ -d "$_REPO_HOME" ]]; then
    log_info "Using local repo at $_REPO_HOME"
    "$CHEZMOI_BIN" init --apply --source "$_REPO_HOME"
else
    log_info "Initialising from GitHub ($GITHUB_REPO)"
    "$CHEZMOI_BIN" init --apply "https://github.com/${GITHUB_REPO}.git"
fi

log_ok "Dotfiles applied"

# Resolve install dir via chezmoi if we bootstrapped from GitHub
if [[ ! -d "$INSTALL_DIR" ]]; then
    INSTALL_DIR="$("$CHEZMOI_BIN" source-path)/install"
fi

### 3. packages ###

log_section "3 — packages"

case "$OS" in
    darwin)
        log_info "macOS — installing Homebrew packages"
        bash "$INSTALL_DIR/homebrew.sh"
        ;;
    linux)
        log_info "Linux — installing Nix packages"
        bash "$INSTALL_DIR/nix.sh"
        ;;
    *)
        log_warn "Unknown OS '$OS' — skipping package install"
        ;;
esac

### 4. mise (language runtimes) ###

log_section "4 — mise"
bash "$INSTALL_DIR/mise.sh"

### 5. optional tools ###

log_section "5 — optional tools"

if [[ "${INSTALL_RUST:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/rust.sh"
else
    log_info "Skipping Rust (INSTALL_RUST=0)"
fi

if [[ "${INSTALL_PYTHON:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/python.sh"
else
    log_info "Skipping Python (INSTALL_PYTHON=0)"
fi

if [[ "${INSTALL_CLAUDE:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/claude.sh"
else
    log_info "Skipping Claude plugins (INSTALL_CLAUDE=0)"
fi

### done ###

log_section "bootstrap complete"
log_ok "Done! Open a new shell or: source ~/.zprofile"
log_info ""
log_info "Day-to-day:"
log_info "  chezmoi update          — pull + apply latest dotfile changes"
log_info "  chezmoi edit ~/.zshrc   — edit a dotfile"
log_info "  chezmoi diff            — preview pending changes"
