#!/usr/bin/env bash
# install/quarto.sh — rootless Linux Quarto install; macOS uses the Brew cask.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Quarto"

QUARTO_VERSION="${DF_QUARTO_VERSION:-1.10.18}"

if [[ "$OS" == "darwin" ]]; then
    if has quarto; then
        log_okay "Quarto: $(quarto --version 2>&1 | head -1)"
    else
        log_warn "Quarto is managed by the macOS Homebrew cask; re-run package installation"
    fi
    exit 0
fi

case "$ARCH" in
    x86_64) _quarto_arch="amd64" ;;
    aarch64) _quarto_arch="arm64" ;;
    *)
        log_warn "No rootless Quarto archive configured for Linux $ARCH"
        exit 0
        ;;
esac

_quarto_name="quarto-${QUARTO_VERSION}-linux-${_quarto_arch}.tar.gz"
_quarto_base="https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}"
_quarto_dir="$LOCAL_PLAT/quarto/$QUARTO_VERSION"
_quarto_bin="$_quarto_dir/bin/quarto"

if [[ -x "$_quarto_bin" ]]; then
    log_okay "Quarto $QUARTO_VERSION already installed: $_quarto_dir"
else
    _quarto_tmp="$(mktemp -d)"
    trap 'rm -rf -- "$_quarto_tmp"' EXIT
    _quarto_archive="$_quarto_tmp/$_quarto_name"
    _quarto_checksums="$_quarto_tmp/quarto-${QUARTO_VERSION}-checksums.txt"

    log_info "Downloading Quarto $QUARTO_VERSION for Linux $_quarto_arch"
    download "$_quarto_base/$_quarto_name" "$_quarto_archive"
    download "$_quarto_base/quarto-${QUARTO_VERSION}-checksums.txt" "$_quarto_checksums"
    _quarto_sha="$(awk -v name="$_quarto_name" '$NF == name { print $1; exit }' "$_quarto_checksums")"
    [[ -n "$_quarto_sha" ]] || die "Quarto checksum missing for $_quarto_name"
    if has sha256sum; then
        printf '%s  %s\n' "$_quarto_sha" "$_quarto_archive" \
            | sha256sum --check --status || die "Quarto checksum verification failed"
    elif has shasum; then
        printf '%s  %s\n' "$_quarto_sha" "$_quarto_archive" \
            | shasum -a 256 --check --status || die "Quarto checksum verification failed"
    else
        die "Quarto checksum verification needs sha256sum or shasum"
    fi

    tar -xzf "$_quarto_archive" -C "$_quarto_tmp"
    [[ -x "$_quarto_tmp/quarto-${QUARTO_VERSION}/bin/quarto" ]] \
        || die "Quarto archive layout changed"
    ensure_dir "$(dirname "$_quarto_dir")"
    # A failed older attempt may have left the version directory incomplete.
    [[ ! -e "$_quarto_dir" && ! -L "$_quarto_dir" ]] || rm -rf -- "$_quarto_dir"
    mv "$_quarto_tmp/quarto-${QUARTO_VERSION}" "$_quarto_dir"
    rm -rf "$_quarto_tmp"
    trap - EXIT
    log_okay "Installed Quarto $QUARTO_VERSION → $_quarto_dir"
fi

ensure_dir "$ARCH_BIN"
if [[ -e "$ARCH_BIN/quarto" && ! -L "$ARCH_BIN/quarto" ]]; then
    log_warn "Not replacing non-symlink $ARCH_BIN/quarto"
else
    ln -sfn "$_quarto_bin" "$ARCH_BIN/quarto"
fi

if [[ -x "$ARCH_BIN/quarto" ]]; then
    log_okay "Quarto: $($_quarto_bin --version 2>&1 | head -1)"
fi
