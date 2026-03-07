#!/usr/bin/env sh
# install/chezmoi.sh - install chezmoi to arch-specific bin dir (no sudo)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"

if [ -x "$CHEZMOI_BIN" ]; then
    log_ok "chezmoi already installed at $CHEZMOI_BIN ($("$CHEZMOI_BIN" --version 2>&1 | head -1))"
    exit 0
fi

ensure_dir "$ARCH_BIN"

log_info "Installing chezmoi for $OS/$ARCH → $ARCH_BIN"

CHEZMOI_VERSION=$(
    curl -fsSL "https://api.github.com/repos/twpayne/chezmoi/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/'
)

case "$OS" in
    darwin) GOOS="darwin" ;;
    linux)  GOOS="linux" ;;
    *)      log_error "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
    aarch64) GOARCH="arm64" ;;
    x86_64)  GOARCH="amd64" ;;
    *)       log_error "Unsupported arch: $ARCH"; exit 1 ;;
esac

URL="https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_${GOOS}_${GOARCH}.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log_info "Downloading chezmoi v${CHEZMOI_VERSION} from GitHub"
download "$URL" "$TMP/chezmoi.tar.gz"
tar -xzf "$TMP/chezmoi.tar.gz" -C "$TMP" chezmoi
install -m 755 "$TMP/chezmoi" "$CHEZMOI_BIN"

log_ok "chezmoi installed: $("$CHEZMOI_BIN" --version)"
