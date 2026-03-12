#!/usr/bin/env bash
# install/zsh.sh - install oh-my-zsh, pure prompt, and zsh plugins
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "ZSH (oh-my-zsh + plugins)"

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"

### oh-my-zsh ###

if [[ -f "$ZSH_DIR/oh-my-zsh.sh" ]]; then
    log_ok "oh-my-zsh already installed"
else
    log_info "Installing oh-my-zsh → $ZSH_DIR"
    # If ZSH_DIR is a symlink to an empty dir (scratch.sh creates this),
    # resolve to the real target — oh-my-zsh installer refuses to clone
    # into an existing path, but we can remove the empty real dir and
    # let it re-create it via git clone.
    _install_target="$ZSH_DIR"
    if [[ -L "$ZSH_DIR" ]]; then
        _install_target="$(readlink -f "$ZSH_DIR")"
    fi
    if [[ -d "$_install_target" ]] && [[ -z "$(ls -A "$_install_target")" ]]; then
        rmdir "$_install_target"
    fi
    # RUNZSH=no:    don't launch a new shell at the end of install
    # CHSH=no:      don't try to change the default shell
    # KEEP_ZSHRC=yes: don't overwrite ~/.zshrc (chezmoi manages it)
    # REMOTE: use HTTPS so this works in environments without SSH keys (CI, Docker)
    # ZSH: set to resolved path so installer creates it via git clone
    ZSH="$_install_target" RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        REMOTE=https://github.com/ohmyzsh/ohmyzsh.git \
        run_logged bash <(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)
    log_ok "oh-my-zsh installed"
fi

### helper to clone or update a plugin/theme ###

_clone_or_update() {
    local name="$1" url="$2" dest="$3"
    if [[ -d "$dest/.git" ]]; then
        log_ok "$name already installed — updating"
        git -C "$dest" pull --ff-only --quiet
    else
        log_info "Installing $name → $dest"
        ensure_dir "$(dirname "$dest")"
        run_logged git clone --depth=1 "$url" "$dest"
        log_ok "$name installed"
    fi
}

### pure prompt (theme) ###

_clone_or_update "pure" \
    "https://github.com/sindresorhus/pure.git" \
    "$ZSH_CUSTOM/themes/pure"

### plugins ###

_clone_or_update "zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

_clone_or_update "fast-syntax-highlighting" \
    "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" \
    "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"

_clone_or_update "zsh-completions" \
    "https://github.com/zsh-users/zsh-completions.git" \
    "$ZSH_CUSTOM/plugins/zsh-completions"

log_ok "ZSH plugins up to date"
