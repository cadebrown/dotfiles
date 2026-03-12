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
# All per-machine tool paths live under ~/.local/$PLAT/:
#   ~/.local/$PLAT/bin/         chezmoi, uv, uvx, and other compiled tools
#   ~/.local/$PLAT/nvm/         nvm install + node versions — NVM_DIR
#   ~/.local/$PLAT/nix-profile/ Nix user profile (symlink into /nix/store) — NIX_PROFILE
#   ~/.local/$PLAT/rustup/      Rust toolchain — RUSTUP_HOME
#   ~/.local/$PLAT/cargo/       Cargo home — CARGO_HOME (bins at cargo/bin/)
#   ~/.local/$PLAT/venv/        Python virtualenv — VENV
#
# ~/.local/bin/ stays on PATH for arch-neutral shell scripts only.
#
# On a new machine sharing a home directory, simply re-run bootstrap.sh.
# chezmoi finds the cached config (no prompts), dotfiles are already applied,
# and only the PLAT-specific tool installs run.
PLAT="$(uname -m)-$(uname -s)"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
[[ "$OS" == "darwin" ]] && OS="darwin" || OS="linux"

ARCH="$(uname -m)"
# Normalize to aarch64: macOS reports arm64, Linux reports aarch64 for the same ISA.
# Using aarch64 everywhere avoids per-OS conditionals in install scripts.
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"

# Resolve LOCAL_PLAT through any symlink so tool configs (rustup, cargo, nvm)
# store the real physical path. This prevents stale config entries if ~/.local
# is ever re-pointed (e.g. scratch remount or layout change).
_LOCAL_ROOT="$HOME/.local"
if [[ -L "$_LOCAL_ROOT" ]]; then
    _LOCAL_ROOT="$(readlink -f "$_LOCAL_ROOT")"
fi
LOCAL_PLAT="$_LOCAL_ROOT/$PLAT"
unset _LOCAL_ROOT
ARCH_BIN="$LOCAL_PLAT/bin"

# Standard per-machine tool paths — install scripts and shell both use these
RUSTUP_HOME="${RUSTUP_HOME:-$LOCAL_PLAT/rustup}"
CARGO_HOME="${CARGO_HOME:-$LOCAL_PLAT/cargo}"
# macOS Sequoia+ blocks ar/ld from writing .rlib archives in system temp
# (/var/folders/.../T/). Redirect cargo build artifacts to a home-dir path.
# This is needed even with Homebrew's code-signed rustup when binstall falls
# back to source compilation for packages without pre-built binaries.
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$LOCAL_PLAT/cargo-build}"
VENV="${VENV:-$LOCAL_PLAT/venv}"

# uv: keep all arch-specific uv state under LOCAL_PLAT
# UV_TOOL_BIN_DIR: where `uv tool install` places binaries (default ~/.local/bin — wrong for shared homes)
# UV_TOOL_DIR:     tool metadata (venvs etc.)
# UV_PYTHON_INSTALL_DIR: managed Python downloads (compiled binaries, must be PLAT-specific)
UV_TOOL_BIN_DIR="${UV_TOOL_BIN_DIR:-$ARCH_BIN}"
UV_TOOL_DIR="${UV_TOOL_DIR:-$LOCAL_PLAT/uv/tools}"
UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$LOCAL_PLAT/uv/python}"

# nvm: node version manager — installed per-PLAT so arch-specific node binaries
# don't collide across machines sharing an NFS home directory.
NVM_DIR="${NVM_DIR:-$LOCAL_PLAT/nvm}"

# Nix: ~/.nix-profile is a symlink into /nix/store — it must be PLAT-specific
# because /nix/store is machine-local and the symlink target doesn't exist on
# the other arch's machine. NIX_PROFILE is respected by both nix and home-manager.
NIX_PROFILE="${NIX_PROFILE:-$LOCAL_PLAT/nix-profile}"

# Scratch space for NFS homes with small quotas.
#
# When scratch is configured, install/scratch.sh symlinks large home dirs
# from $HOME into $PATHS/ (a subdir of scratch), keeping the NFS home lean.
#
# How to configure (pick one):
#   a) Create ~/scratch as a symlink to large local storage:
#        ln -s /local/disk/$USER ~/scratch
#   b) Set DOTFILES_SCRATCH_PATH before running bootstrap:
#        DOTFILES_SCRATCH_PATH=/local/disk/$USER ~/dotfiles/bootstrap.sh
#
# Variable reference (PATH/LINK pattern):
#   DOTFILES_SCRATCH_PATH  — actual scratch directory on local disk
#   DOTFILES_SCRATCH_LINK  — symlink in $HOME pointing to scratch (default: ~/scratch)
#                            bootstrap.sh creates this symlink if DOTFILES_SCRATCH_PATH is set.
#   DOTFILES_LINKS_PATHS   — colon-separated list of home dirs to redirect to scratch
#                            (default: ~/.local:~/.cache)
#   SCRATCH                — resolved absolute path to scratch root (empty if none)
#   PATHS                  — $SCRATCH/.paths — where all symlinked dirs live:
#                              $PATHS/.local/        ← ~/.local
#                              $PATHS/.cache/        ← ~/.cache
#                              $PATHS/.oh-my-zsh/    ← ~/.oh-my-zsh
#                              $PATHS/.oh-my-zsh-custom/ ← ~/.oh-my-zsh-custom
#                              $PATHS/.config/       ← ~/.config (if in DOTFILES_LINKS_PATHS)
#
# Downstream variables (all under $PATHS/.local/$PLAT/ when scratch is used):
#   LOCAL_PLAT        = $HOME/.local/$PLAT          (logical path, may be via symlink)
#   ARCH_BIN          = $LOCAL_PLAT/bin             chezmoi, uv, uvx
#   RUSTUP_HOME       = $LOCAL_PLAT/rustup          Rust toolchain
#   CARGO_HOME        = $LOCAL_PLAT/cargo           Cargo (bins at cargo/bin/)
#   CARGO_TARGET_DIR  = $LOCAL_PLAT/cargo-build     build artifacts (macOS sandbox workaround)
#   VENV              = $LOCAL_PLAT/venv            Python virtualenv
#   UV_TOOL_BIN_DIR   = $LOCAL_PLAT/bin             uv tool binaries
#   UV_TOOL_DIR       = $LOCAL_PLAT/uv/tools        uv tool metadata
#   UV_PYTHON_INSTALL_DIR = $LOCAL_PLAT/uv/python   uv-managed Python builds
#   NVM_DIR           = $LOCAL_PLAT/nvm             nvm + Node versions
#   NIX_PROFILE       = $LOCAL_PLAT/nix-profile     Nix user profile
#   BREW_PREFIX       = $LOCAL_PLAT/brew            Homebrew (Linux native install)
DOTFILES_SCRATCH_PATH="${DOTFILES_SCRATCH_PATH:-}"
DOTFILES_SCRATCH_LINK="${DOTFILES_SCRATCH_LINK:-$HOME/scratch}"
if [[ -z "${DOTFILES_SCRATCH_PATH:-}" && -e "$DOTFILES_SCRATCH_LINK" ]]; then
    DOTFILES_SCRATCH_PATH="$(cd "$DOTFILES_SCRATCH_LINK" && pwd -P)"
fi
SCRATCH="${DOTFILES_SCRATCH_PATH:-}"
PATHS="${SCRATCH:+$SCRATCH/.paths}"
export DOTFILES_SCRATCH_PATH DOTFILES_SCRATCH_LINK SCRATCH PATHS

export PLAT LOCAL_PLAT RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR VENV \
       UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR \
       NVM_DIR NIX_PROFILE

# Install scripts clone public repos and must not be affected by the user's
# gitconfig (which may have url.insteadOf SSH rewrites, breaking clones on
# machines without SSH keys — Docker, CI, fresh Linux boxes).
export GIT_CONFIG_GLOBAL=/dev/null

# Source credential env files (e.g. ~/.nvidia.env with GITHUB_TOKEN) so that
# install scripts can authenticate with GitHub APIs (cargo-binstall, gh, etc.).
# Uses bash globbing — no error if no files match.
for _envfile in "$HOME"/.*.env; do
    [[ -f "$_envfile" ]] && source "$_envfile"
done
unset _envfile

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
