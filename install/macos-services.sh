#!/usr/bin/env bash
# install/macos-services.sh - macOS post-install wiring: login services (launchd) + CLI plugins
#
# The local backend services (colima container runtime, ollama, mlxserve LLM
# server) do NOT auto-start by default — mlxserve alone reserves ~34GB RAM at
# login, and none of the three are needed for day-to-day work. Set
# DF_START_LOCAL_SERVICES=1 to restore auto-start on bootstrap. Manual control
# stays available regardless: `colima start`, `ollama serve`, `mlxserve`.
# The docker CLI-plugin symlinks below always run (so a manual `colima start`
# gives a working `docker compose` / `docker buildx`).
# Re-running is safe: all steps are idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Services (auto-start)"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — no services to configure"; exit 0; }

# Auto-start of colima/ollama/mlxserve is opt-in (see header). Default off.
: "${DF_START_LOCAL_SERVICES:=0}"

### colima ###
# Container runtime — provides a Docker-compatible socket for the `docker` CLI.
# After this, `docker` works without Docker Desktop.

if [[ "$DF_START_LOCAL_SERVICES" != "1" ]]; then
    log_okay "colima auto-start disabled (DF_START_LOCAL_SERVICES=0) — 'colima start' to run manually"
elif has colima; then
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

### ollama ###
# Local LLM inference server — OpenAI-compatible API on localhost:11434.
# Two install paths:
#   - Homebrew formula (`brew install ollama`): managed via `brew services`
#   - macOS app (/Applications/Ollama.app): manages its own LaunchAgent

if [[ "$DF_START_LOCAL_SERVICES" != "1" ]]; then
    log_okay "ollama auto-start disabled (DF_START_LOCAL_SERVICES=0) — 'ollama serve' to run manually"
elif has ollama; then
    if [[ -d "/Applications/Ollama.app" ]]; then
        # App install handles its own LaunchAgent — brew services is irrelevant here.
        # Checking brew first was wrong: the app's agent can appear in brew services
        # output as "started", giving a misleading "brew service" log message.
        log_okay "ollama installed as macOS app (manages its own LaunchAgent)"
    elif brew services list 2>/dev/null | grep -q '^ollama.*started'; then
        log_okay "ollama already running as a brew service"
    elif brew list ollama &>/dev/null 2>&1; then
        log_info "Starting ollama service (auto-start at login)"
        if run_logged brew services start ollama; then
            log_okay "ollama service registered"
        else
            log_warn "ollama service start failed — run 'brew services start ollama' manually"
        fi
    else
        log_warn "ollama found but source unknown — start manually: ollama serve"
    fi
else
    log_warn "ollama not found — skipping (run install/homebrew.sh first)"
fi

### mlxserve (mlx-openai-server) ###
# Local LLM server on :8080 used as the default backend by opencode/pi.
# Without this LaunchAgent, those tools fail to connect on first launch unless
# the user remembered to start mlxserve manually.
#
# The plist itself (deployed by chezmoi) holds the model + parser config.
# This block loads it into the user's launchd domain (idempotent: bootstraps
# once, then no-ops on subsequent runs).

_MLX_PLIST="$HOME/Library/LaunchAgents/dev.cade.mlxserve.plist"
_MLX_LABEL="dev.cade.mlxserve"

if [[ "$DF_START_LOCAL_SERVICES" != "1" ]]; then
    log_okay "mlxserve auto-start disabled (DF_START_LOCAL_SERVICES=0) — 'mlxserve' to run manually"
elif [[ -f "$_MLX_PLIST" ]]; then
    if ! has mlx-openai-server; then
        log_warn "mlx-openai-server not installed — LaunchAgent will fail to start"
        log_warn "  fix: uv tool install mlx-openai-server"
    fi
    mkdir -p "$HOME/.local/share/mlxserve"
    if launchctl print "gui/$(id -u)/$_MLX_LABEL" &>/dev/null; then
        log_okay "mlxserve LaunchAgent already loaded ($_MLX_LABEL)"
    else
        log_info "Loading mlxserve LaunchAgent (auto-start at login)"
        if launchctl bootstrap "gui/$(id -u)" "$_MLX_PLIST" 2>/dev/null; then
            log_okay "mlxserve LaunchAgent loaded — first run downloads ~25GB Qwen weights"
        else
            log_warn "launchctl bootstrap failed — try manually: launchctl bootstrap gui/\$UID $_MLX_PLIST"
        fi
    fi
else
    log_warn "mlxserve plist missing — chezmoi apply may not have run yet"
fi
unset _MLX_PLIST _MLX_LABEL

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
