#!/usr/bin/env bash
# install/macos-services.sh - macOS post-install wiring: login services (launchd) + CLI plugins
#
# Services: started now AND registered for auto-start at login.
# Re-running is safe: all steps are idempotent.
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

### docker CLI plugins ###
# docker-compose and docker-buildx are installed by Homebrew but must be
# symlinked into ~/.docker/cli-plugins/ to work as `docker compose` / `docker buildx`.

_BREW_PREFIX="$(brew --prefix 2>/dev/null)" || _BREW_PREFIX=""
if [[ -n "$_BREW_PREFIX" ]]; then
    mkdir -p "$HOME/.docker/cli-plugins"

    _COMPOSE_BIN="$_BREW_PREFIX/opt/docker-compose/bin/docker-compose"
    if [[ -f "$_COMPOSE_BIN" ]]; then
        ln -sfn "$_COMPOSE_BIN" "$HOME/.docker/cli-plugins/docker-compose"
        log_okay "docker-compose plugin linked"
    else
        log_warn "docker-compose binary not found — run 'brew install docker-compose' first"
    fi

    _BUILDX_BIN="$_BREW_PREFIX/opt/docker-buildx/bin/docker-buildx"
    if [[ -f "$_BUILDX_BIN" ]]; then
        ln -sfn "$_BUILDX_BIN" "$HOME/.docker/cli-plugins/docker-buildx"
        log_okay "docker-buildx plugin linked"
    else
        log_warn "docker-buildx binary not found — run 'brew install docker-buildx' first"
    fi

    unset _COMPOSE_BIN _BUILDX_BIN
else
    log_warn "brew not found — skipping docker CLI plugin setup"
fi
unset _BREW_PREFIX

log_okay "Services configured"
