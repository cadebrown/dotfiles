#!/usr/bin/env bash
# install/codex.sh - install OpenAI Codex CLI
#
# Downloads the native binary from GitHub releases and places it in
# $ARCH_BIN (PLAT-isolated for shared home directory safety).
# Works on both macOS and Linux — no Homebrew cask needed.
#
# To update, re-run this script — it always downloads latest.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Codex CLI"

# Build the asset name for this platform
case "$OS" in
    darwin)
        case "$ARCH" in
            aarch64) _asset="codex-aarch64-apple-darwin" ;;
            x86_64)  _asset="codex-x86_64-apple-darwin" ;;
            *) die "Unsupported architecture: $ARCH" ;;
        esac
        ;;
    linux)
        # Use musl on Alpine or when glibc < 2.38 (codex gnu binary requires 2.38+).
        _glibc_ver=$(ldd --version 2>/dev/null | awk 'NR==1 {print $NF}')
        _glibc_maj="${_glibc_ver%%.*}"
        _glibc_min="${_glibc_ver##*.}"
        if ldd --version 2>&1 | grep -q musl; then
            _libc="musl"
        elif [[ "$_glibc_maj" -lt 2 || ("$_glibc_maj" -eq 2 && "$_glibc_min" -lt 38) ]]; then
            log_info "glibc $_glibc_ver < 2.38 — using musl build"
            _libc="musl"
        else
            _libc="gnu"
        fi
        unset _glibc_ver _glibc_maj _glibc_min
        case "$ARCH" in
            aarch64) _asset="codex-aarch64-unknown-linux-${_libc}" ;;
            x86_64)  _asset="codex-x86_64-unknown-linux-${_libc}" ;;
            *) die "Unsupported architecture: $ARCH" ;;
        esac
        unset _libc
        ;;
    *) die "Unsupported OS: $OS" ;;
esac

# Get latest version tag from GitHub
log_info "Fetching latest version..."
_release_url=$(curl -fsSL -o /dev/null -w "%{url_effective}" "https://github.com/openai/codex/releases/latest" 2>/dev/null)
_version="${_release_url##*/}"  # e.g. rust-v0.114.0
_semver="${_version#rust-v}"    # e.g. 0.114.0
log_info "Latest: $_semver"

_dest="$ARCH_BIN/codex"

# Skip if already on this version
if [[ -x "$_dest" ]] && "$_dest" --version 2>/dev/null | grep -qF "$_semver"; then
    log_okay "codex $_semver already installed at $_dest"
else
    log_info "Downloading codex $_semver ($_asset)..."
    ensure_dir "$ARCH_BIN"

    _tmp="$(mktemp -d)"
    trap 'rm -rf "$_tmp"' RETURN

    _url="https://github.com/openai/codex/releases/download/${_version}/${_asset}.tar.gz"
    download "$_url" "$_tmp/codex.tar.gz"
    tar xzf "$_tmp/codex.tar.gz" -C "$_tmp"

    # Verify the extracted binary is non-empty and executable
    if [[ ! -s "$_tmp/$_asset" ]]; then
        die "Downloaded codex binary is empty — possible corrupt download"
    fi

    mv "$_tmp/$_asset" "$_dest"
    chmod +x "$_dest"

    # Smoke test: ensure the binary runs
    if ! "$_dest" --version &>/dev/null; then
        rm -f "$_dest"
        die "codex binary smoke test failed — removed $_dest"
    fi

    log_okay "Installed codex $_semver → $_dest"
fi

unset _asset _release_url _version _semver _dest _url _tmp
