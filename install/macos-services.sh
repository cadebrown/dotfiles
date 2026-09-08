#!/usr/bin/env bash
# install/macos-services.sh - macOS post-install wiring: login services (launchd) + CLI plugins
#
# The local backend services (colima container runtime, ollama, mlxserve LLM
# server) do NOT auto-start by default — mlxserve alone reserves ~34GB RAM at
# login, and none of the three are needed for day-to-day work. Set
# DF_START_LOCAL_SERVICES=1 to restore auto-start on bootstrap. Manual control
# stays available regardless: `colima start`, `ollama serve`, `mlxserve`.
# colima/ollama are skip-only when the flag is off (brew services state is
# already persistent); mlxserve is actively booted out and disabled, because
# launchd auto-loads its plist from ~/Library/LaunchAgents at every login.
# The docker CLI-plugin symlinks below always run (so a manual `colima start`
# gives a working `docker compose` / `docker buildx`).
# Re-running is safe: all steps are idempotent.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_start_ollama_formula() {
    if ! has brew || ! brew list ollama >/dev/null 2>&1; then
        log_fail "Ollama's Homebrew formula is missing — run install/homebrew.sh"
        return 1
    fi
    if pgrep -u "$(id -u)" -f '^/Applications/Ollama.app/Contents/Resources/ollama( |$)' >/dev/null; then
        log_fail "Ollama.app owns the running server; quit it before starting the Homebrew service"
        return 1
    fi
    if brew services list 2>/dev/null | grep -q '^ollama.*started'; then
        log_okay "ollama already running as a brew service"
    else
        run_logged brew services start ollama || return 1
        log_okay "ollama Homebrew service registered"
    fi
}

_ollama_app_server_pids() {
    pgrep -u "$(id -u)" -f '^/Applications/Ollama[.]app/Contents/Resources/ollama serve$' || true
}

_stop_ollama_app_pid() {
    local _pid="$1" _expected="$2" _identity _current _attempt
    _current="$(ps -p "$_pid" -o command=)" || return 0
    [[ "$_current" == "$_expected" ]] || return 1
    _identity="$(ps -p "$_pid" -o lstart= -o command=)" || return 0
    kill -TERM "$_pid" || return 1
    for _attempt in {1..50}; do
        _current="$(ps -p "$_pid" -o lstart= -o command= 2>/dev/null)" || return 0
        [[ "$_current" == "$_identity" ]] || return 0
        sleep 0.2
    done
    log_fail "Ollama process $_pid did not stop after SIGTERM; no forced kill sent"
    return 1
}

_ollama_model_inventory() {
    curl --noproxy '*' -fsS --max-time 5 http://127.0.0.1:11434/api/tags \
        | jq -ce '[.models[] | {name,digest}] | sort_by(.name)'
}

_stop_ollama_app_runtime() {
    local _pid="$1" _app_pids="$2" _app_pid
    launchctl disable "gui/$(id -u)/com.ollama.ollama" || return 1
    if launchctl print "gui/$(id -u)/com.ollama.ollama" >/dev/null 2>&1; then
        launchctl bootout "gui/$(id -u)/com.ollama.ollama" || return 1
    fi
    for _app_pid in $_app_pids; do
        _stop_ollama_app_pid "$_app_pid" /Applications/Ollama.app/Contents/MacOS/Ollama || return 1
    done
    _stop_ollama_app_pid "$_pid" '/Applications/Ollama.app/Contents/Resources/ollama serve'
}

_reconcile_ollama_owner() {
    local _pids _pid _app_pids _formula _models _loaded _connections _backup _disabled _attempt _after _listener
    _pids="$(_ollama_app_server_pids)"
    [[ -n "$_pids" ]] || return 0
    [[ "$_pids" != *$'\n'* ]] || { log_fail "Multiple Ollama.app servers found; leave them unchanged"; return 1; }
    _pid="$_pids"
    has brew && has jq && has lsof || { log_fail "Ollama migration needs brew, jq, and lsof"; return 1; }
    brew list --formula ollama >/dev/null 2>&1 || { log_fail "Install the Ollama formula before migrating its app server"; return 1; }
    _formula="$(brew --prefix ollama)/bin/ollama"
    run_bounded 10 "$_formula" --version >/dev/null || return 1
    _listener="$(lsof -nP -a -p "$_pid" -iTCP:11434 -sTCP:LISTEN -t)" || return 1
    [[ "$_listener" == "$_pid" ]] || { log_fail "App server does not own port 11434; no process changed"; return 1; }
    _loaded="$(curl --noproxy '*' -fsS --max-time 5 http://127.0.0.1:11434/api/ps | jq -er '.models | length')" || return 1
    [[ "$_loaded" == 0 ]] || { log_fail "Ollama has loaded models; retry ownership migration after they are unloaded"; return 1; }
    if ! _connections="$(lsof -nP -a -p "$_pid" -iTCP -sTCP:ESTABLISHED 2>&1)" && [[ -n "$_connections" ]]; then
        log_fail "Could not verify Ollama connection state; no process changed"
        return 1
    fi
    [[ -z "$_connections" ]] || { log_fail "Ollama has active connections; retry ownership migration after requests finish"; return 1; }
    _models="$(_ollama_model_inventory)" || return 1
    _backup="$LOCAL_PLAT/share/dotfiles/rollback/ollama-app"
    ensure_dir "$_backup"
    chmod 700 "$_backup"
    _backup="$(mktemp -d "$_backup/migration.XXXXXX")" || return 1
    printf '%s\n' "$_models" > "$_backup/models-before.json"
    _disabled="$(launchctl print-disabled "gui/$(id -u)")" || return 1
    printf '%s\n' "$_disabled" > "$_backup/launchctl-disabled-before.txt"
    _app_pids="$(pgrep -u "$(id -u)" -f '^/Applications/Ollama[.]app/Contents/MacOS/Ollama$' || true)"
    local _mode=run _healthy=0 _formula_attempted=0
    [[ "${DF_START_LOCAL_SERVICES:-0}" != 1 ]] || _mode=start
    if _stop_ollama_app_runtime "$_pid" "$_app_pids"; then
        _formula_attempted=1
        if run_logged brew services "$_mode" ollama; then
            for _attempt in {1..30}; do
                if _after="$(_ollama_model_inventory 2>/dev/null)" && [[ "$_after" == "$_models" ]]; then
                    _healthy=1
                    break
                fi
                sleep 0.2
            done
        fi
    fi
    if [[ "$_healthy" == 1 ]]; then
        printf '%s\n' "$_after" > "$_backup/models-after.json"
        log_okay "Ollama migrated to the formula with model inventory preserved (service mode: $_mode)"
        return 0
    fi
    log_fail "Formula service failed verification; restoring the Ollama app backend"
    if [[ "$_formula_attempted" == 1 ]]; then
        brew services stop ollama >/dev/null 2>&1 || return 1
    fi
    if ! grep -Eq '"com[.]ollama[.]ollama"[[:space:]]*=>[[:space:]]*(true|disabled)' <<< "$_disabled"; then
        launchctl enable "gui/$(id -u)/com.ollama.ollama" || return 1
    fi
    open -g -a /Applications/Ollama.app || return 1
    log_fail "App restart requested; inspect $_backup and retry after checking the formula"
    return 1
}

[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

log_section "Services (auto-start)"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — no services to configure"; exit 0; }

# Auto-start of colima/ollama/mlxserve is opt-in (see header). Default off.
: "${DF_START_LOCAL_SERVICES:=0}"

### colima ###
# Container runtime — provides a Docker-compatible socket for the `docker` CLI.
# After this, `docker` works without Docker Desktop.

_set_colima_ssh_config_false() {
    local _file="$1" _tmp _mode
    [[ ! -L "$_file" ]] || return 1
    _tmp="$(mktemp "${_file}.tmp.XXXXXX")" || return 1

    if ! awk '
        BEGIN { found = 0 }
        /^sshConfig:[[:space:]]*/ {
            if (!found) print "sshConfig: false"
            found = 1
            next
        }
        { print }
        END { if (!found) print "sshConfig: false" }
    ' "$_file" > "$_tmp"; then
        rm -f "$_tmp"
        return 1
    fi

    if stat --version >/dev/null 2>&1; then
        _mode="$(stat -c '%a' "$_file")"
    else
        _mode="$(stat -f '%Lp' "$_file")"
    fi
    chmod "$_mode" "$_tmp"
    if cmp -s "$_file" "$_tmp"; then
        rm -f "$_tmp"
    else
        mv -f "$_tmp" "$_file"
    fi
}

_configure_colima_ssh() {
    local _template _root _config
    _template="$(colima template --print)" \
        || die "Unable to locate the Colima configuration template"
    case "$_template" in
        /*/_templates/*.yaml) ;;
        *) die "Unexpected Colima template path: $_template" ;;
    esac

    if [[ ! -f "$_template" ]]; then
        # Sparse templates replace Colima's CLI defaults with zero values.
        colima template --editor /usr/bin/true >/dev/null \
            || die "Unable to initialize the Colima configuration template"
    fi
    _set_colima_ssh_config_false "$_template" \
        || die "Unable to disable Colima SSH config injection in $_template"

    _root="$(dirname "$(dirname "$_template")")"
    for _config in "$_root"/*/colima.yaml; do
        [[ -f "$_config" ]] || continue
        _set_colima_ssh_config_false "$_config" \
            || die "Unable to disable Colima SSH config injection in $_config"
    done
    log_okay "colima SSH config injection disabled"
}

if has colima; then
    _configure_colima_ssh
fi

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
unset -f _set_colima_ssh_config_false _configure_colima_ssh

### ollama ###
# Local LLM inference server — OpenAI-compatible API on localhost:11434.
# The Brewfile formula owns the server and its service lifecycle.

_reconcile_ollama_owner || die "Ollama ownership reconciliation failed"
if [[ "$DF_START_LOCAL_SERVICES" != "1" ]]; then
    log_okay "ollama auto-start disabled (DF_START_LOCAL_SERVICES=0) — 'ollama serve' to run manually"
else
    _start_ollama_formula || die "could not start the declared Ollama service"
fi

### mlxserve (mlx-openai-server) ###
# Local LLM server on :8080 used as the default backend by opencode/pi.
# Without this LaunchAgent, those tools fail to connect on first launch unless
# the user remembered to start mlxserve manually.
#
# The plist itself (deployed by chezmoi) holds the model + parser config.
#
# launchd auto-loads every plist in ~/Library/LaunchAgents at login, so skipping
# the bootstrap is not enough to keep the agent off — the disabled-override
# database is the only thing that survives a re-login. Hence both branches below
# are active: off explicitly boots out + disables, on re-enables before
# bootstrapping (a stale override makes bootstrap succeed but never run).

_MLX_PLIST="$HOME/Library/LaunchAgents/dev.cade.mlxserve.plist"
_MLX_LABEL="dev.cade.mlxserve"
_MLX_DOMAIN="gui/$(id -u)"

if [[ "$DF_START_LOCAL_SERVICES" != "1" ]]; then
    if launchctl print "$_MLX_DOMAIN/$_MLX_LABEL" &>/dev/null; then
        log_info "Unloading mlxserve LaunchAgent (DF_START_LOCAL_SERVICES=0)"
        launchctl bootout "$_MLX_DOMAIN/$_MLX_LABEL" 2>/dev/null || true
    fi
    launchctl disable "$_MLX_DOMAIN/$_MLX_LABEL" 2>/dev/null || true
    log_okay "mlxserve auto-start disabled (DF_START_LOCAL_SERVICES=0) — 'mlxserve' to run manually"
elif [[ -f "$_MLX_PLIST" ]]; then
    if ! has mlx-openai-server; then
        log_warn "mlx-openai-server not installed — LaunchAgent will fail to start"
        log_warn "  fix: uv tool install mlx-openai-server"
    fi
    mkdir -p "$HOME/.local/share/mlxserve"
    launchctl enable "$_MLX_DOMAIN/$_MLX_LABEL" 2>/dev/null || true
    if launchctl print "$_MLX_DOMAIN/$_MLX_LABEL" &>/dev/null; then
        log_okay "mlxserve LaunchAgent already loaded ($_MLX_LABEL)"
    else
        log_info "Loading mlxserve LaunchAgent (auto-start at login)"
        if launchctl bootstrap "$_MLX_DOMAIN" "$_MLX_PLIST" 2>/dev/null; then
            log_okay "mlxserve LaunchAgent loaded — first run downloads ~25GB Qwen weights"
        else
            log_warn "launchctl bootstrap failed — try manually: launchctl bootstrap $_MLX_DOMAIN $_MLX_PLIST"
        fi
    fi
else
    log_warn "mlxserve plist missing — chezmoi apply may not have run yet"
fi
unset _MLX_PLIST _MLX_LABEL _MLX_DOMAIN

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
