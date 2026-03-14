#!/usr/bin/env bash
# install/_lib.sh - shared helpers for all install scripts
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

set -euo pipefail

### COLORS ###

# Respect NO_COLOR convention and non-interactive output
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    _RESET='\033[0m'
    _BOLD='\033[1m'
    _DIM='\033[2m'
    _BLUE='\033[0;34m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _RED='\033[0;31m'
    _CYAN='\033[0;36m'
    _WHITE='\033[1;37m'
else
    _RESET='' _BOLD='' _DIM='' _BLUE='' _GREEN='' _YELLOW='' _RED='' _CYAN='' _WHITE=''
fi

### LOGGING ###

DF_DEBUG="${DF_DEBUG:-0}"

log_info()    { printf "${_BLUE}${_BOLD}[info]${_RESET}  %s\n"    "$*"; }
log_okay()    { printf "${_GREEN}${_BOLD}[okay]${_RESET}  %s\n"   "$*"; }
log_warn()    { printf "${_YELLOW}${_BOLD}[warn]${_RESET}  %s\n"  "$*"; }
log_fail()    { printf "${_RED}${_BOLD}[fail]${_RESET}  %s\n"     "$*" >&2; }
log_debug()   { [[ "$DF_DEBUG" == "1" ]] && printf "${_CYAN}[dbug]${_RESET}  ${_DIM}%s${_RESET}\n" "$*" || true; }

_SECTION_START=$SECONDS
log_section() {
    local _prev_elapsed=$(( SECONDS - _SECTION_START ))
    # Print elapsed time of previous section (skip if first section or < 1s)
    if [[ "$DF_DEBUG" == "1" && "$_prev_elapsed" -gt 0 ]]; then
        printf "${_DIM}      (${_prev_elapsed}s)${_RESET}\n"
    fi
    printf "\n${_WHITE}=== %s ===${_RESET}\n\n" "$*"
    _SECTION_START=$SECONDS
}

die() {
    log_fail "$*"
    exit 1
}

### ERROR TRAP ###

_on_error() {
    local exit_code=$?
    local line=$1
    log_fail "Script failed at line $line (exit code $exit_code)"
    exit "$exit_code"
}
trap '_on_error $LINENO' ERR

### PATHS ###

# Root of the dotfiles repo (parent of install/)
DF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DF_PACKAGES="$DF_ROOT/packages"

### PLATFORM ###

# PLAT identifies the current platform, used to isolate compiled binaries
# in shared home directories (e.g. NFS mounts across x86_64 and aarch64).
# All per-machine tool paths live under ~/.local/$PLAT/:
#   ~/.local/$PLAT/bin/         chezmoi, uv, uvx, and other compiled tools
#   ~/.local/$PLAT/nvm/         nvm install + node versions — NVM_DIR
#   ~/.local/$PLAT/rustup/      Rust toolchain — RUSTUP_HOME
#   ~/.local/$PLAT/cargo/       Cargo home — CARGO_HOME (bins at cargo/bin/)
#   ~/.local/$PLAT/venv/        Python virtualenv — VENV
#
# ~/.local/bin/ stays on PATH for arch-neutral shell scripts only.
#
# PLAT format: plat_{OS}_{cpu-target} (e.g. plat_Linux_x86-64-v3, plat_Darwin_arm64)
# Detection: scan install/plat/plat_${OS}_*/ dirs (highest level first), run
# .plat_check.sh, pick the first that exits 0. Also sources .plat_env.sh to
# set CFLAGS, RUSTFLAGS, HOMEBREW_OPTFLAGS, etc. for that CPU target.
#
# If no spec matches, _lib.sh dies — add a new spec for unsupported platforms.
#
# On a new machine sharing a home directory, simply re-run bootstrap.sh.
# chezmoi finds the cached config (no prompts), dotfiles are already applied,
# and only the PLAT-specific tool installs run.

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

# PLAT detection: scan install/plat/ for .plat_check.sh scripts.
# Sorted reverse = highest level first (v4 > v3 > v2).
PLAT=""
_PLAT_SCRIPT_DIR="$DF_ROOT/install/plat"
if [[ -d "$_PLAT_SCRIPT_DIR" ]]; then
    _PLAT_OS="$(uname -s)"
    while IFS= read -r _plat_dir; do
        _check="$_plat_dir/.plat_check.sh"
        if [[ -f "$_check" ]] && /bin/sh "$_check" 2>/dev/null; then
            PLAT="$(basename "$_plat_dir")"
            [[ -f "$_plat_dir/.plat_env.sh" ]] && source "$_plat_dir/.plat_env.sh"
            break
        fi
    done < <(ls -1d "$_PLAT_SCRIPT_DIR"/plat_"${_PLAT_OS}"_*/ 2>/dev/null | sort -r)
    unset _PLAT_OS _plat_dir _check
fi
unset _PLAT_SCRIPT_DIR

# No matching plat spec — fatal. Ensure install/plat/ has a spec for this machine.
if [[ -z "$PLAT" ]]; then
    die "No matching plat spec in $DF_ROOT/install/plat/ for $(uname -s) $(uname -m)"
fi

LOCAL_PLAT="$_LOCAL_ROOT/$PLAT"
unset _LOCAL_ROOT
ARCH_BIN="$LOCAL_PLAT/bin"

# Standard per-machine tool paths — always derived from LOCAL_PLAT.
# Never inherit from env (stale RUSTUP_HOME etc. causes installs to wrong dir).
RUSTUP_HOME="$LOCAL_PLAT/rustup"
CARGO_HOME="$LOCAL_PLAT/cargo"
# macOS Sequoia+ blocks ar/ld from writing .rlib archives in system temp
# (/var/folders/.../T/). Redirect cargo build artifacts to a home-dir path.
CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"
VENV="$LOCAL_PLAT/venv"

# uv: keep all arch-specific state under LOCAL_PLAT
UV_TOOL_BIN_DIR="$ARCH_BIN"
UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"

# nvm: per-PLAT so arch-specific node binaries don't collide on shared homes
NVM_DIR="$LOCAL_PLAT/nvm"

# Scratch space for NFS homes with small quotas.
#
# When scratch is configured, install/scratch.sh symlinks large home dirs
# from $HOME into $PATHS/ (a subdir of scratch), keeping the NFS home lean.
#
# How to configure (pick one):
#   a) Create ~/scratch as a symlink to large local storage:
#        ln -s /local/disk/$USER ~/scratch
#   b) Set DF_SCRATCH before running bootstrap:
#        DF_SCRATCH=/local/disk/$USER ~/dotfiles/bootstrap.sh
#
# Variable reference:
#   DF_SCRATCH       — actual scratch directory on local disk
#   DF_SCRATCH_LINK  — symlink in $HOME pointing to scratch (default: ~/scratch)
#                      bootstrap.sh creates this symlink if DF_SCRATCH is set.
#   DF_LINKS         — colon-separated list of home dirs to redirect to scratch
#                      (default: ~/.local:~/.cache)
#   SCRATCH          — resolved absolute path to scratch root (empty if none)
#   PATHS            — $SCRATCH/.paths — where all symlinked dirs live

DF_SCRATCH="${DF_SCRATCH:-}"
DF_SCRATCH_LINK="${DF_SCRATCH_LINK:-$HOME/scratch}"
if [[ -z "${DF_SCRATCH:-}" && -e "$DF_SCRATCH_LINK" ]]; then
    DF_SCRATCH="$(cd "$DF_SCRATCH_LINK" && pwd -P)"
fi
SCRATCH="${DF_SCRATCH:-}"
PATHS="${SCRATCH:+$SCRATCH/.paths}"
export DF_SCRATCH DF_SCRATCH_LINK SCRATCH PATHS

export PLAT LOCAL_PLAT RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR VENV \
       UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR \
       NVM_DIR

# Install scripts clone public repos and must not be affected by the user's
# gitconfig (which may have url.insteadOf SSH rewrites, breaking clones on
# machines without SSH keys — Docker, CI, fresh Linux boxes).
export GIT_CONFIG_GLOBAL=/dev/null

# Source credential env files (e.g. ~/.github.env with GITHUB_TOKEN) so that
# install scripts can authenticate with GitHub APIs (cargo-binstall, gh, etc.).
# Uses bash globbing — no error if no files match.
for _envfile in "$HOME"/.*.env; do
    [[ -f "$_envfile" ]] && source "$_envfile"
done
unset _envfile

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
    log_debug "exec: $*"
    local _start=$SECONDS
    "$@" 2>&1 | sed 's/^/    /'
    local _rc=${PIPESTATUS[0]}
    if [[ "$DF_DEBUG" == "1" ]]; then
        log_debug "exit=$_rc elapsed=$(( SECONDS - _start ))s"
    fi
    return "$_rc"
}

# Re-derive all PLAT-dependent variables from the current LOCAL_PLAT.
# Call this after LOCAL_PLAT changes (e.g. scratch symlink resolution,
# PLAT re-detection in bootstrap.sh).
_re_derive_plat_vars() {
    ARCH_BIN="$LOCAL_PLAT/bin"
    RUSTUP_HOME="$LOCAL_PLAT/rustup"
    CARGO_HOME="$LOCAL_PLAT/cargo"
    CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"
    VENV="$LOCAL_PLAT/venv"
    UV_TOOL_BIN_DIR="$ARCH_BIN"
    UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
    UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"
    NVM_DIR="$LOCAL_PLAT/nvm"
    export LOCAL_PLAT ARCH_BIN RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR VENV \
           UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR NVM_DIR
}

# Read a package list file, skipping blank lines and comments.
# Outputs one package name per line (strips trailing comments/args).
_read_package_list() {
    local file="$1"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        printf '%s\n' "${line%% *}"
    done < "$file"
}
