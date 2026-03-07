#!/usr/bin/env bash
# install/chezmoi.sh - install chezmoi to arch-specific bin (no sudo)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"

if [[ -x "$CHEZMOI_BIN" ]]; then
    log_ok "Already installed: $("$CHEZMOI_BIN" --version)"
    exit 0
fi

ensure_dir "$ARCH_BIN"
log_info "Installing chezmoi → $ARCH_BIN"

# Use the official installer — handles version, OS, arch, and checksum verification
run_logged bash <(curl -fsSL https://get.chezmoi.io) -b "$ARCH_BIN"

log_ok "Installed: $("$CHEZMOI_BIN" --version)"
