#!/usr/bin/env bash
# install/linux-packages.sh - install packages on Linux via Homebrew
#
# Runs Homebrew directly on the host — no container, no Docker, no sudo.
# Homebrew installs its own glibc 2.35 so binaries are self-contained and
# portable across Linux systems regardless of the host glibc version.
#
# Most packages pour as precompiled bottles. glibc builds from source (~2 min)
# on first install and is installed explicitly before brew bundle so that all
# subsequent bottles link against Homebrew's glibc rather than the system one.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_warn "Not on Linux — skipping"; exit 0; }

log_section "Linux packages (Homebrew)"

BREW_PREFIX="${BREW_PREFIX:-$LOCAL_PLAT/brew}"
log_info "Homebrew prefix:   $BREW_PREFIX"

### Resolve symlinks ###
# readlink -f so paths are real filesystem paths (NFS homes may have symlinks).
mkdir -p "$BREW_PREFIX"
_REAL_BREW_PREFIX="$(readlink -f "$BREW_PREFIX")"
_REAL_LOCAL_PLAT="$(dirname "$_REAL_BREW_PREFIX")"

_BREWFILE_TMP="$_REAL_LOCAL_PLAT/.Brewfile"
trap 'rm -f "$_BREWFILE_TMP" 2>/dev/null || true' EXIT
cp "$PACKAGES_DIR/Brewfile" "$_BREWFILE_TMP"

log_info "Resolved prefix:   $_REAL_BREW_PREFIX"
log_info "Brewfile:          $_BREWFILE_TMP"

### Install Homebrew ###

if [[ ! -x "$_REAL_BREW_PREFIX/bin/brew" ]]; then
    log_info "Installing Homebrew → $_REAL_BREW_PREFIX"
    git clone --depth=1 https://github.com/Homebrew/brew "$_REAL_BREW_PREFIX/Homebrew"
    mkdir -p "$_REAL_BREW_PREFIX/bin"
    ln -sf "$_REAL_BREW_PREFIX/Homebrew/bin/brew" "$_REAL_BREW_PREFIX/bin/brew"
else
    log_ok "Homebrew already installed at $_REAL_BREW_PREFIX"
fi

# Capture git path before brew shellenv modifies PATH.
_GIT_PATH="$(command -v git 2>/dev/null || true)"
eval "$($_REAL_BREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
[[ -n "$_GIT_PATH" ]] && export HOMEBREW_GIT_PATH="$_GIT_PATH"
unset _GIT_PATH

### Install glibc first ###
#
# Homebrew's glibc (2.35) makes all bottles self-contained — binaries use
# Homebrew's own loader (brew/lib/ld.so → opt/glibc/bin/ld.so) which resolves
# libc from the Cellar rather than the host system. Without this step, machines
# whose system glibc is already ≥ 2.35 would skip glibc and binaries would
# silently depend on the host glibc — breaking portability to older systems.
if brew list glibc &>/dev/null; then
    log_ok "glibc already installed"
else
    log_info "Installing glibc (builds from source, ~2 min)..."
    brew install glibc 2>&1
fi

### Install all packages ###

log_info "Running brew bundle..."
brew bundle install --file="$_BREWFILE_TMP" --no-upgrade 2>&1

log_ok "Linux packages installed at $_REAL_BREW_PREFIX"
log_info "Activate with: eval \"\$($_REAL_BREW_PREFIX/bin/brew shellenv)\""
