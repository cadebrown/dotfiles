#!/usr/bin/env bash
# install/services.sh - register macOS login services via launchd (brew services)
#
# Each entry here starts the service now AND makes it auto-start at login.
# Re-running is safe: brew services start is idempotent (already-running = no-op).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Services (auto-start)"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — no services to configure"; exit 0; }

### colima ###
# Container runtime — provides a Docker-compatible socket for the `docker` CLI.
# After this, `docker` works without Docker Desktop.

if has colima; then
    if brew services list | grep -q '^colima.*started'; then
        log_okay "colima already running as a service"
    else
        log_info "Starting colima service (auto-start at login)"
        if run_logged brew services start colima; then
            log_okay "colima service registered"
        else
            log_warn "colima service start failed — run 'brew services start colima' manually"
        fi
    fi
else
    log_warn "colima not found — skipping (run install/homebrew.sh first)"
fi

log_okay "Services configured"
