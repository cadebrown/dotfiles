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
#   CHEZMOI_NAME     — pre-seed display name (skips interactive prompt)
#   CHEZMOI_EMAIL    — pre-seed email (skips interactive prompt)
#   INSTALL_PACKAGES — set to 0 to skip package install (Homebrew on macOS/Linux)
#   INSTALL_SERVICES — set to 0 to skip auto-start service registration
#   INSTALL_ZSH      — set to 0 to skip oh-my-zsh + plugins install
#   INSTALL_NODE     — set to 0 to skip Node install
#   INSTALL_NPM      — set to 0 to skip global npm packages
#   INSTALL_RUST     — set to 0 to skip Rust install
#   INSTALL_PYTHON   — set to 0 to skip Python install
#   INSTALL_CLAUDE   — set to 0 to skip Claude Code plugins install

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

# Pre-seed name/email from env so chezmoi doesn't prompt — useful for CI and
# unattended installs. promptStringOnce checks the config file first, so if
# chezmoi.toml already exists (re-run on same machine), this is a no-op.
if [[ -n "${CHEZMOI_NAME:-}" || -n "${CHEZMOI_EMAIL:-}" ]]; then
    _CFG="$HOME/.config/chezmoi/chezmoi.toml"
    if [[ ! -f "$_CFG" ]]; then
        ensure_dir "$(dirname "$_CFG")"
        printf '[data]\n  name  = "%s"\n  email = "%s"\n' \
            "${CHEZMOI_NAME:-}" "${CHEZMOI_EMAIL:-}" > "$_CFG"
        log_info "Pre-seeded chezmoi config from CHEZMOI_NAME / CHEZMOI_EMAIL"
    fi
fi

# If we're running from inside the repo, use it as the source directly
_REPO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/home"
if [[ -d "$_REPO_HOME" ]]; then
    log_info "Using local repo at $_REPO_HOME"
    "$CHEZMOI_BIN" init --apply --force --source "$_REPO_HOME"
    # Persist sourceDir so subsequent chezmoi commands (diff, apply, update)
    # work without needing --source each time. Not needed for GitHub-based init
    # since chezmoi clones to ~/.local/share/chezmoi/ automatically.
    _CFG="$HOME/.config/chezmoi/chezmoi.toml"
    if ! grep -q "sourceDir" "$_CFG" 2>/dev/null; then
        # sourceDir must be a top-level TOML key — prepend it before [data]
        # so it isn't parsed as data.sourceDir
        _tmp="$(mktemp)"
        printf 'sourceDir = "%s"\n\n' "$_REPO_HOME" > "$_tmp"
        cat "$_CFG" >> "$_tmp"
        mv "$_tmp" "$_CFG"
        log_info "Set chezmoi sourceDir to $_REPO_HOME"
    fi
else
    log_info "Initialising from GitHub ($GITHUB_REPO)"
    "$CHEZMOI_BIN" init --apply --force "https://github.com/${GITHUB_REPO}.git"
fi

log_ok "Dotfiles applied"

# Resolve install dir via chezmoi if we bootstrapped from GitHub
if [[ ! -d "$INSTALL_DIR" ]]; then
    # source-path points to home/ (via .chezmoiroot), install/ is one level up
    INSTALL_DIR="$(dirname "$("$CHEZMOI_BIN" source-path)")/install"
fi

### 3. ZSH ###

log_section "3 — ZSH (oh-my-zsh + plugins)"

if [[ "${INSTALL_ZSH:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/zsh.sh"
else
    log_info "Skipping ZSH plugins (INSTALL_ZSH=0)"
fi

### 4. packages ###

log_section "4 — packages (Homebrew)"

if [[ "${INSTALL_PACKAGES:-1}" != "0" ]]; then
    case "$OS" in
        darwin)
            log_info "macOS — Homebrew (native bottles)"
            bash "$INSTALL_DIR/homebrew.sh"
            ;;
        linux)
            log_info "Linux — Homebrew in manylinux_2_28 container"
            bash "$INSTALL_DIR/linux-packages.sh"
            # Activate brew for the rest of this bootstrap session
            BREW_BIN="$LOCAL_PLAT/brew/bin/brew"
            if [[ -x "$BREW_BIN" ]]; then
                eval "$("$BREW_BIN" shellenv)"
            fi
            ;;
        *)
            log_warn "Unknown OS '$OS' — skipping package install"
            ;;
    esac
else
    log_info "Skipping packages (INSTALL_PACKAGES=0)"
fi

### 5. services ###

log_section "5 — services"

if [[ "${INSTALL_SERVICES:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/services.sh"
else
    log_info "Skipping services (INSTALL_SERVICES=0)"
fi

### 6. language runtimes ###

log_section "6 — language runtimes"

if [[ "${INSTALL_NODE:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/node.sh"
    # Activate nvm for the rest of this bootstrap session so npm.sh can use it
    # shellcheck source=/dev/null
    [[ -s "$LOCAL_PLAT/nvm/nvm.sh" ]] && source "$LOCAL_PLAT/nvm/nvm.sh" && nvm use default --silent 2>/dev/null || true
else
    log_info "Skipping Node (INSTALL_NODE=0)"
fi

if [[ "${INSTALL_NPM:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/npm.sh"
else
    log_info "Skipping npm packages (INSTALL_NPM=0)"
fi

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
