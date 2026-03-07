#!/usr/bin/env bash
# bootstrap.sh - set up a new machine from scratch
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
#
# Usage (from cloned repo):
#   git clone https://github.com/cadebrown/dotfiles && cd dotfiles && ./bootstrap.sh
set -e

### DETECT LOCATION ###

# If running via curl | sh, we don't have a local repo yet.
# DOTFILES_DIR is set if running from a cloned repo.
DOTFILES_DIR="${DOTFILES_DIR:-}"
GITHUB_REPO="${GITHUB_REPO:-cadebrown/dotfiles}"

. "$(dirname "$0")/install/_lib.sh" 2>/dev/null || {
    # Not running from repo — download _lib.sh temporarily
    TMP_LIB="$(mktemp)"
    trap 'rm -f "$TMP_LIB"' EXIT
    curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/install/_lib.sh" -o "$TMP_LIB"
    . "$TMP_LIB"
}

log_section "dotfiles bootstrap"
log_info "OS: $OS | Arch: $ARCH"

### 1. CHEZMOI ###

log_section "1/5  chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"
ensure_dir "$ARCH_BIN"

if [ ! -x "$CHEZMOI_BIN" ] && ! has chezmoi; then
    log_info "Installing chezmoi"
    INSTALL_DIR="$ARCH_BIN" sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b "$ARCH_BIN"
    log_ok "chezmoi installed: $("$CHEZMOI_BIN" --version)"
else
    log_ok "chezmoi already available"
    CHEZMOI_BIN="$(has chezmoi && command -v chezmoi || echo "$CHEZMOI_BIN")"
fi

### 2. DOTFILES via CHEZMOI ###

log_section "2/5  dotfiles (chezmoi apply)"

if [ -n "$DOTFILES_DIR" ] && [ -d "$DOTFILES_DIR" ]; then
    # Running from a cloned repo: use it directly
    log_info "Using local dotfiles at $DOTFILES_DIR"
    "$CHEZMOI_BIN" init --apply --source "$DOTFILES_DIR/home"
else
    # Bootstrap from GitHub
    log_info "Initialising chezmoi from GitHub ($GITHUB_REPO)"
    "$CHEZMOI_BIN" init --apply "https://github.com/${GITHUB_REPO}.git"
fi

log_ok "dotfiles applied"

### 3. PACKAGES ###

log_section "3/5  packages"

INSTALL_DIR="$(dirname "$0")/install"

# Resolve install dir if we're in the repo
if [ ! -d "$INSTALL_DIR" ]; then
    INSTALL_DIR="$("$CHEZMOI_BIN" source-path 2>/dev/null | sed 's|/home$||')/install"
fi

case "$OS" in
    darwin)
        log_info "macOS detected — running Homebrew install"
        sh "$INSTALL_DIR/homebrew.sh"
        ;;
    linux)
        log_info "Linux detected — running Nix install (if available)"
        if has nix || sh "$INSTALL_DIR/nix.sh" 2>/dev/null; then
            log_ok "Nix packages applied"
        else
            log_warn "Nix install skipped or failed — install packages manually"
        fi
        ;;
esac

### 4. MISE (language runtimes) ###

log_section "4/5  mise"
sh "$INSTALL_DIR/mise.sh"

### 5. OPTIONAL TOOLS ###

log_section "5/5  optional tools"

if [ "${INSTALL_RUST:-1}" = "1" ]; then
    sh "$INSTALL_DIR/rust.sh"
fi

if [ "${INSTALL_PYTHON:-1}" = "1" ]; then
    sh "$INSTALL_DIR/python.sh"
fi

### DONE ###

log_section "bootstrap complete"
log_ok "All done! Start a new shell or run: source ~/.zprofile"
log_info "Key commands:"
log_info "  chezmoi update       — pull latest dotfile changes"
log_info "  chezmoi edit ~/.zshrc — edit a dotfile"
log_info "  chezmoi diff         — preview pending changes"
