#!/usr/bin/env bash
# install/_lib.sh - shared helpers for all install scripts
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

set -euo pipefail

### PATHS ###

# Root of the dotfiles repo (parent of install/)
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="$DOTFILES_ROOT/packages"

### PLATFORM ###

# PLAT identifies the current arch+OS, used to isolate compiled binaries
# in shared home directories (e.g. NFS mounts across x86_64 and aarch64).
# All per-machine tool paths are suffixed with PLAT:
#   ~/.local/bin/$PLAT    chezmoi and other compiled tools
#   ~/.nvm-$PLAT          Node (nvm)
#   ~/.rustup-$PLAT       Rust toolchain (rustup)
#   ~/.cargo-$PLAT        Rust binaries (cargo)
#   ~/.venv-$PLAT         Python virtualenv
#
# On a new machine sharing a home directory, simply re-run bootstrap.sh.
# chezmoi finds the cached config (no prompts), dotfiles are already applied,
# and only the PLAT-specific tool installs run.
PLAT="$(uname -m)-$(uname -s)"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
[[ "$OS" == "darwin" ]] && OS="darwin" || OS="linux"

ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"  # normalize macOS arm64

ARCH_BIN="$HOME/.local/bin/$PLAT"

# Standard per-machine tool paths — install scripts and shell both use these
NVM_DIR="${NVM_DIR:-$HOME/.nvm-$PLAT}"
RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup-$PLAT}"
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo-$PLAT}"
VENV="${VENV:-$HOME/.venv-$PLAT}"

export PLAT NVM_DIR RUSTUP_HOME CARGO_HOME VENV

### COLORS ###

# Respect NO_COLOR convention and non-interactive output
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    _RESET='\033[0m'
    _BLUE='\033[0;34m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _RED='\033[0;31m'
    _BOLD='\033[1;37m'
else
    _RESET='' _BLUE='' _GREEN='' _YELLOW='' _RED='' _BOLD=''
fi

### LOGGING ###

log_info()    { printf "${_BLUE}[info]${_RESET}  %s\n"    "$*"; }
log_ok()      { printf "${_GREEN}[ ok ]${_RESET}  %s\n"   "$*"; }
log_warn()    { printf "${_YELLOW}[warn]${_RESET}  %s\n"  "$*"; }
log_error()   { printf "${_RED}[err ]${_RESET}  %s\n"     "$*" >&2; }
log_section() { printf "\n${_BOLD}=== %s ===${_RESET}\n"  "$*"; }

die() {
    log_error "$*"
    exit 1
}

### ERROR TRAP ###

_on_error() {
    local exit_code=$?
    local line=$1
    log_error "Script failed at line $line (exit code $exit_code)"
    exit "$exit_code"
}
trap '_on_error $LINENO' ERR

### UTILITIES ###

has() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

download() {
    local url="$1" dest="$2"
    if has curl; then
        curl -fsSL "$url" -o "$dest"
    elif has wget; then
        wget -q "$url" -O "$dest"
    else
        die "Neither curl nor wget found — cannot download files"
    fi
}

run_logged() {
    "$@" 2>&1 | sed 's/^/    /'
}
