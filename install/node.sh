#!/usr/bin/env bash
# install/node.sh - install Node.js LTS via nvm
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Node.js (nvm)"

NVM_VERSION="${DF_NVM_VERSION:-v0.40.6}"
NODE_MAJOR="${DF_NODE_MAJOR:-24}"
NPM_MAJOR="${DF_NPM_MAJOR:-11}"

# nvm goes under LOCAL_PLAT so each arch+OS gets its own node binaries
# (nvm itself is shell scripts, but the node versions it installs are arch-specific)

# PROFILE=/dev/null: don't touch shell configs (chezmoi manages those)
_nvm_install() {
    local _nvm_script
    _nvm_script="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" -o "$_nvm_script"
    NVM_DIR="$NVM_DIR" PROFILE=/dev/null run_logged bash "$_nvm_script"
    rm -f "$_nvm_script"
}

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    log_info "Installing nvm..."
    ensure_dir "$NVM_DIR"
    _nvm_install
fi

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

_nvm_current="v$(nvm --version)"
if [[ "$_nvm_current" != "$NVM_VERSION" ]]; then
    log_info "Updating nvm: $_nvm_current → $NVM_VERSION"
    _nvm_install
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
else
    log_okay "nvm $NVM_VERSION already installed: $NVM_DIR"
fi
unset _nvm_current

if nvm ls "$NODE_MAJOR" 2>/dev/null | grep -qE "v${NODE_MAJOR}\."; then
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        _node_cur="$(nvm version "$NODE_MAJOR")"
        # nvm's legacy io.js lookup hangs under Bash 5.3; LTS-only resolution skips it.
        _node_remote="$(NVM_LTS="*" nvm version-remote "$NODE_MAJOR")"
        if [[ "$_node_cur" != "$_node_remote" ]]; then
            log_info "Upgrading Node.js v$NODE_MAJOR: $_node_cur → $_node_remote"
            run_logged nvm install --lts "$NODE_MAJOR"
        else
            log_okay "Node v$NODE_MAJOR already latest ($_node_cur)"
        fi
    else
        log_okay "Node v$NODE_MAJOR already installed"
    fi
else
    log_info "Installing Node.js v$NODE_MAJOR..."
    run_logged nvm install --lts "$NODE_MAJOR"
fi

nvm alias default "$NODE_MAJOR"

# Put nvm's bin at the front before activating. `nvm use` rewrites an existing
# nvm entry in PATH *in place* rather than prepending, so it cannot recover the
# ordering once something else has moved ahead of it — and under bootstrap `brew
# shellenv` has done exactly that. Every `node`/`npm` below then runs Homebrew's
# keg instead of the version nvm just selected. Aug 2026: a half-finished brew
# dependency upgrade left that keg unable to start (`libllhttp.so.9.3`), and it
# took the whole script down while nvm's own node sat there working.
_nvm_node="$(nvm which default 2>/dev/null || true)"
if [[ -x "$_nvm_node" ]]; then
    _nvm_bin="$(dirname "$_nvm_node")"
    PATH="$_nvm_bin:$PATH"
    export PATH
    unset _nvm_bin
fi
unset _nvm_node

nvm use default --silent

_npm_current="$(npm --version)"
_npm_repair=0
if [[ "${_npm_current%%.*}" != "$NPM_MAJOR" ]]; then
    log_info "Aligning npm: $_npm_current → v$NPM_MAJOR"
    run_logged npm install -g "npm@$NPM_MAJOR"
    _npm_repair=1
elif [[ "${DF_MODE:-}" == "upgrade" ]]; then
    run_logged npm install -g "npm@$NPM_MAJOR"
fi
unset _npm_current

log_okay "Node.js: $(node --version)"
log_okay "npm:     $(npm --version)"

# Native npm packages use node-gyp when no prebuilt binary exists. Python is
# installed earlier in bootstrap; point node-gyp at uv's interpreter because
# uv-managed Python does not add a generic `python3` executable to PATH.
if [[ -x "$ARCH_BIN/uv" ]]; then
    _node_gyp_python="$("$ARCH_BIN/uv" python find 2>/dev/null || true)"
    if [[ -n "$_node_gyp_python" ]]; then
        export PYTHON="$_node_gyp_python"
        log_debug "node-gyp Python: $PYTHON"
    fi
fi

### npm global packages ###

NPM_TXT="$DF_PACKAGES/npm.txt"
if [[ ! -f "$NPM_TXT" ]]; then
    log_warn "No npm.txt at $NPM_TXT — skipping npm packages"
    exit 0
fi

_npm_allow_scripts=""
if [[ -f "$DF_PACKAGES/npm-allow-scripts.txt" ]]; then
    while IFS= read -r _script_pkg; do
        if [[ -n "$_npm_allow_scripts" ]]; then
            _npm_allow_scripts="${_npm_allow_scripts},${_script_pkg}"
        else
            _npm_allow_scripts="$_script_pkg"
        fi
    done < <(_read_package_list "$DF_PACKAGES/npm-allow-scripts.txt")
fi
_npm_allow_args=()
[[ -n "$_npm_allow_scripts" ]] && _npm_allow_args=("--allow-scripts=$_npm_allow_scripts")

_pkg_count=0
_upgrade_count=0
_qmd_stopped=0
while IFS= read -r pkg; do
    # Entries may pin a version ("<name>@1.2.3", scoped names keep their
    # leading @). Split at the LAST @ — a tail with "/" in it is the package
    # path of a scoped name, not a version.
    _name="$pkg" _pin="" _tail="${pkg##*@}"
    if [[ "$pkg" == *"@"* && -n "$_tail" && "$_tail" != *"/"* && "$pkg" != "@$_tail" ]]; then
        _name="${pkg%@*}"
        _pin="$_tail"
    fi

    if [[ -n "$_pin" ]]; then
        # Pinned: hold this exact version; upgrade mode does not move it.
        if npm list -g "${_name}@${_pin}" --depth=0 &>/dev/null; then
            log_okay "  $_name@$_pin (pinned, installed)"
            if [[ "$_npm_repair" == "1" ]]; then
                run_logged npm install -g "${_npm_allow_args[@]}" "${_name}@${_pin}"
            fi
            # Never SILENTLY stale: in upgrade mode, surface the pin-vs-latest
            # delta loudly so a held package is a visible decision, not a
            # forgotten one. Nothing is pinned today; codex was, for binary/
            # config lockstep, and npm.txt says to re-pin it if that recurs.
            if [[ "${DF_MODE:-}" == "upgrade" ]]; then
                _latest="$(npm view "$_name" version 2>/dev/null || true)"
                if [[ -n "$_latest" && "$_latest" != "$_pin" ]]; then
                    log_warn "  $_name HELD at $_pin — latest is $_latest. Bump the pin in packages/npm.txt deliberately, then re-run that package's install script check."
                fi
            fi
        else
            log_info "  installing $_name@$_pin (pinned)"
            run_logged npm install -g "${_npm_allow_args[@]}" "${_name}@${_pin}"
            log_okay "  $_name@$_pin"
            (( _pkg_count++ )) || true
        fi
    elif npm list -g "$_name" --depth=0 &>/dev/null; then
        if [[ "$_npm_repair" == "1" ]]; then
            run_logged npm install -g "${_npm_allow_args[@]}" "$_name"
        elif [[ "${DF_MODE:-}" == "upgrade" ]]; then
            log_info "  upgrading $_name"
            # qmd runs a persistent MCP daemon that mmaps native addons; on an
            # NFS home npm can't unlink them mid-upgrade (EBUSY on .nfs*
            # silly-renames) while it runs. Stop it here, restart after the
            # loop. Linux only — macOS uses launchd + a local FS (no EBUSY).
            # See docs/usage/troubleshooting.md.
            if [[ "$OS" == "linux" && "$_name" == "@tobilu/qmd" ]] && qmd_daemon_running; then
                log_info "  stopping qmd daemon for safe upgrade (NFS EBUSY guard)"
                qmd_daemon_stop && _qmd_stopped=1
            fi
            run_logged npm install -g "${_npm_allow_args[@]}" "$_name@latest"
            log_okay "  $_name (upgraded)"
            (( _upgrade_count++ )) || true
        else
            log_okay "  $_name (already installed)"
        fi
    else
        log_info "  installing $_name"
        run_logged npm install -g "${_npm_allow_args[@]}" "$_name"
        log_okay "  $_name"
        (( _pkg_count++ )) || true
    fi
done < <(_read_package_list "$NPM_TXT")

# Bring the qmd MCP daemon back if we stopped it for its upgrade. In a full
# bootstrap memory.sh (step 6.6) would also restart it, but node.sh can run
# standalone, so don't leave the memory daemon dead.
if [[ "$_qmd_stopped" == "1" ]]; then
    qmd_daemon_start && log_okay "  restarted qmd mcp daemon"
fi

if [[ $_pkg_count -eq 0 && $_upgrade_count -eq 0 ]]; then
    log_info "All npm packages already installed"
fi
