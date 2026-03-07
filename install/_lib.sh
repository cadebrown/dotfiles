#!/usr/bin/env bash
# install/_lib.sh - shared helpers for all install scripts
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

set -euo pipefail

### PATHS ###

# Root of the dotfiles repo (parent of install/)
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="$DOTFILES_ROOT/packages"

### DETECTION ###

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux"  ;;
        *)      echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x86_64"  ;;
        aarch64|arm64) echo "aarch64" ;;
        *)             echo "$(uname -m)" ;;
    esac
}

# Arch+OS-specific bin directory — compiled binaries live here so shared
# home directories work across machines with different architectures.
arch_bin_dir() {
    echo "$HOME/.local/bin/$(uname -m)-$(uname -s)"
}

OS=$(detect_os)
ARCH=$(detect_arch)
ARCH_BIN="$(arch_bin_dir)"

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

log_info()    { printf "${_BLUE}[info]${_RESET}  %s\n"       "$*"; }
log_ok()      { printf "${_GREEN}[ ok ]${_RESET}  %s\n"      "$*"; }
log_warn()    { printf "${_YELLOW}[warn]${_RESET}  %s\n"     "$*"; }
log_error()   { printf "${_RED}[err ]${_RESET}  %s\n"        "$*" >&2; }
log_section() { printf "\n${_BOLD}=== %s ===${_RESET}\n"     "$*"; }

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

# Check if a command exists
has() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# Download a URL to a destination file
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

# Run a command, prefixing each output line with a marker
run_logged() {
    "$@" 2>&1 | sed 's/^/    /'
}
