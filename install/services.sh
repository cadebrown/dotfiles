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
        log_ok "colima already running as a service"
    else
        log_info "Starting colima service (auto-start at login)"
        run_logged brew services start colima
        log_ok "colima service registered"
    fi
else
    log_warn "colima not found — skipping (run install/homebrew.sh first)"
fi

### iTerm2 ###
# Point iTerm2 at ~/.iterm2 for its preferences (managed by chezmoi).
# These defaults are idempotent — safe to re-run.

if [[ -d "/Applications/iTerm.app" ]]; then
    log_info "Configuring iTerm2 to load prefs from ~/.iterm2"
    defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "$HOME/.iterm2"
    defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true
    defaults write com.googlecode.iterm2.plist "NoSyncNeverRemindPrefsChangesLostForFile_selection" -int 2
    log_ok "iTerm2 prefs configured"
else
    log_info "iTerm2 not installed — skipping prefs setup"
fi
