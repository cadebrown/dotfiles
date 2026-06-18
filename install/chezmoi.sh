#!/usr/bin/env bash
# install/chezmoi.sh - install chezmoi to arch-specific bin (no sudo)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"

if [[ -x "$CHEZMOI_BIN" ]]; then
    # In upgrade mode, self-upgrade the binary that manages everything else —
    # otherwise chezmoi is the one tool `bootstrap upgrade` would leave stale.
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        log_info "Upgrading chezmoi: $("$CHEZMOI_BIN" --version)"
        run_logged "$CHEZMOI_BIN" upgrade || log_warn "chezmoi self-upgrade failed (continuing)"
    fi
    log_okay "Installed: $("$CHEZMOI_BIN" --version)"
    exit 0
fi

ensure_dir "$ARCH_BIN"
log_info "Installing chezmoi → $ARCH_BIN"

# Use the official installer — handles version, OS, arch, and checksum verification
run_logged bash <(curl -fsSL https://get.chezmoi.io) -b "$ARCH_BIN"

log_okay "Installed: $("$CHEZMOI_BIN" --version)"
