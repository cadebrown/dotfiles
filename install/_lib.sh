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

# DF_USE_PLAT controls per-architecture directory isolation. Default: off.
#
# DF_USE_PLAT=0 (default): flat ~/.local/ layout — single-machine setup.
#   Compiled tools live at ~/.local/bin/. Cargo/nvm/uv/rustup state lives at
#   ~/.local/{cargo,nvm,uv,rustup}/. Capability-tuned compiler flags from
#   .plat_env.sh (CFLAGS, RUSTFLAGS, HOMEBREW_OPTFLAGS) are still loaded —
#   PLAT detection is independent of directory layout.
#
# DF_USE_PLAT=1: per-PLAT directory isolation — for shared NFS homes only.
#   Compiled tools live at ~/.local/$PLAT/bin/, etc. Two machines on the same
#   NFS home with different architectures install side-by-side without
#   clobbering each other.
#
# Set DF_USE_PLAT=1 only if you actually share $HOME across machines with
# different CPU architectures (rare). Most users want the default.
#
# PLAT format: plat_{OS}_{cpu-target} (e.g. plat_Linux_x86-64-v3, plat_Darwin_arm64).
# Detection scans install/plat/plat_${OS}_*/ (highest level first), runs
# .plat_check.sh, picks the first that exits 0, then sources .plat_env.sh.

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
[[ "$OS" == "darwin" ]] && OS="darwin" || OS="linux"

ARCH="$(uname -m)"
# Normalize to aarch64: macOS reports arm64, Linux reports aarch64 for the same ISA.
# Using aarch64 everywhere avoids per-OS conditionals in install scripts.
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"

# Normalize DF_USE_PLAT: accept 1/true/yes/on as enabled (matches the chezmoi
# template, which writes use_plat=true|false). Without this, `DF_USE_PLAT=true`
# would silently render profiles PLAT-on while install scripts go flat.
case "${DF_USE_PLAT:-0}" in
    1|true|yes|on|TRUE|YES|ON) DF_USE_PLAT=1 ;;
    *) DF_USE_PLAT=0 ;;
esac

# PLAT detection: scan install/plat/ for .plat_check.sh scripts (highest level first).
# Always run regardless of DF_USE_PLAT — capability flags from .plat_env.sh
# (RUSTFLAGS=-Ctarget-cpu=..., HOMEBREW_OPTFLAGS=-march=..., etc.) are still
# useful in flat mode for binaries this machine actually compiles.
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

# When PLAT isolation is on, a matching spec is required (the directory name
# embeds $PLAT). When off, missing spec is fine — capability flags just don't
# get tuned. Both cases are non-fatal in flat mode.
if [[ "$DF_USE_PLAT" == "1" && -z "$PLAT" ]]; then
    die "DF_USE_PLAT=1 but no matching plat spec in $DF_ROOT/install/plat/ for $(uname -s) $(uname -m)"
fi

# Resolve ~/.local through any symlink so tool configs (rustup, cargo, nvm)
# store the real physical path. Prevents stale entries if ~/.local moves.
_LOCAL_ROOT="$HOME/.local"
if [[ -L "$_LOCAL_ROOT" ]]; then
    _LOCAL_ROOT="$(readlink -f "$_LOCAL_ROOT")"
fi

if [[ "$DF_USE_PLAT" == "1" ]]; then
    LOCAL_PLAT="$_LOCAL_ROOT/$PLAT"
else
    LOCAL_PLAT="$_LOCAL_ROOT"
fi
unset _LOCAL_ROOT
ARCH_BIN="$LOCAL_PLAT/bin"

# Standard per-machine tool paths — always derived from LOCAL_PLAT.
# Never inherit from env (stale RUSTUP_HOME etc. causes installs to wrong dir).
RUSTUP_HOME="$LOCAL_PLAT/rustup"
CARGO_HOME="$LOCAL_PLAT/cargo"
# macOS Sequoia+ blocks ar/ld from writing .rlib archives in system temp
# (/var/folders/.../T/). Redirect cargo build artifacts to a home-dir path.
CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"

# uv: keep all arch-specific state under LOCAL_PLAT
UV_TOOL_BIN_DIR="$ARCH_BIN"
UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"

# nvm: per-PLAT so arch-specific node binaries don't collide on shared homes
NVM_DIR="$LOCAL_PLAT/nvm"

# conan: per-PLAT — cache has compiled binaries, default profile is machine-specific,
# and the cache is not concurrency-safe (multiple NFS clients would corrupt it).
CONAN_HOME="$LOCAL_PLAT/conan2"

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

export OS ARCH DF_ROOT DF_PACKAGES DF_USE_PLAT \
       PLAT LOCAL_PLAT ARCH_BIN RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR \
       UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR \
       NVM_DIR CONAN_HOME

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

### OVERLAYS ###

# Discover overlay repos (dotfiles-*/). Each overlay can provide its own
# packages/ dir mirroring the parent layout (e.g. claude-mcp.txt, cargo.txt).
# Install scripts use overlay_package_files() to iterate over all copies of a
# given package list — base first, then each overlay in sorted order.
#
# Example:
#   while IFS= read -r _file; do
#       _process_entries_from "$_file"
#   done < <(overlay_package_files "claude-mcp.txt")

DF_OVERLAYS=()
for _overlay_dir in "$DF_ROOT"/dotfiles-*/; do
    [[ -d "$_overlay_dir" ]] && DF_OVERLAYS+=("${_overlay_dir%/}")
done
unset _overlay_dir

# Print paths to every copy of a package file: $DF_PACKAGES/<name> first,
# then $overlay/packages/<name> for each overlay that has it.
overlay_package_files() {
    local name="$1" _dir
    [[ -f "$DF_PACKAGES/$name" ]] && printf '%s\n' "$DF_PACKAGES/$name"
    for _dir in "${DF_OVERLAYS[@]}"; do
        [[ -f "$_dir/packages/$name" ]] && printf '%s\n' "$_dir/packages/$name"
    done
    return 0
}

### UTILITIES ###

has() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

download() {
    local url="$1" dest="$2"
    local _auth_header=""

    # GitHub API + asset downloads benefit from authentication: unauthenticated
    # limit is 60 req/hr per IP, authenticated is 5000/hr. Several install
    # scripts (codex, claude, cargo-binstall fallbacks) hit api.github.com or
    # release assets on github.com, and on shared NAT'd networks (CI, NVIDIA
    # GPU clusters) 60/hr is exhausted quickly. Inject Authorization for
    # GitHub-owned hosts only when GITHUB_TOKEN is set. The redirect chain
    # api.github.com → objects.githubusercontent.com stays within GitHub, so
    # forwarding the header on redirect (curl's default) is safe.
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        case "$url" in
            https://api.github.com/*|\
            https://github.com/*|\
            https://*.github.com/*|\
            https://*.githubusercontent.com/*)
                _auth_header="Authorization: Bearer $GITHUB_TOKEN"
                ;;
        esac
    fi

    if has curl; then
        if [[ -n "$_auth_header" ]]; then
            curl -fsSL -H "$_auth_header" "$url" -o "$dest"
        else
            curl -fsSL "$url" -o "$dest"
        fi
    elif has wget; then
        if [[ -n "$_auth_header" ]]; then
            wget -q --header="$_auth_header" "$url" -O "$dest"
        else
            wget -q "$url" -O "$dest"
        fi
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

# Resolve LOCAL_PLAT from current $HOME/.local (handling symlinks) and the
# DF_USE_PLAT flag. Sets LOCAL_PLAT but does NOT touch derived vars — call
# _re_derive_plat_vars after this if anything else has changed.
_resolve_local_plat() {
    local _root="$HOME/.local"
    [[ -L "$_root" ]] && _root="$(readlink -f "$_root")"
    if [[ "${DF_USE_PLAT:-0}" == "1" ]]; then
        LOCAL_PLAT="$_root/$PLAT"
    else
        LOCAL_PLAT="$_root"
    fi
}

# Re-derive all PLAT-dependent variables from the current LOCAL_PLAT.
# Call this after LOCAL_PLAT changes (e.g. scratch symlink resolution,
# PLAT re-detection in bootstrap.sh).
_re_derive_plat_vars() {
    ARCH_BIN="$LOCAL_PLAT/bin"
    RUSTUP_HOME="$LOCAL_PLAT/rustup"
    CARGO_HOME="$LOCAL_PLAT/cargo"
    CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"
    UV_TOOL_BIN_DIR="$ARCH_BIN"
    UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
    UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"
    NVM_DIR="$LOCAL_PLAT/nvm"
    CONAN_HOME="$LOCAL_PLAT/conan2"
    export PLAT LOCAL_PLAT ARCH_BIN RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR \
           UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR NVM_DIR CONAN_HOME
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
