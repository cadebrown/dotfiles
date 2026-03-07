#!/usr/bin/env sh
# install/_lib.sh - shared helpers for install scripts
# Source this file: . "$(dirname "$0")/_lib.sh"

### DETECTION ###

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)         echo "x86_64" ;;
        aarch64|arm64)  echo "aarch64" ;;
        *)              echo "$(uname -m)" ;;
    esac
}

# Arch-specific bin directory (for compiled binaries that can't be shared across arches)
arch_bin_dir() {
    echo "$HOME/.local/bin/$(uname -m)-$(uname -s)"
}

### LOGGING ###

log_info()    { printf '\033[0;34m[info]\033[0m  %s\n' "$*"; }
log_ok()      { printf '\033[0;32m[ ok ]\033[0m  %s\n' "$*"; }
log_warn()    { printf '\033[0;33m[warn]\033[0m  %s\n' "$*"; }
log_error()   { printf '\033[0;31m[err ]\033[0m  %s\n' "$*" >&2; }
log_section() { printf '\n\033[1;37m=== %s ===\033[0m\n' "$*"; }

### UTILITIES ###

has() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
    [ -d "$1" ] || mkdir -p "$1"
}

# Download a file to a path (tries curl then wget)
download() {
    local url="$1"
    local dest="$2"
    if has curl; then
        curl -fsSL "$url" -o "$dest"
    elif has wget; then
        wget -q "$url" -O "$dest"
    else
        log_error "Neither curl nor wget found"
        return 1
    fi
}

OS=$(detect_os)
ARCH=$(detect_arch)
ARCH_BIN="$(arch_bin_dir)"
