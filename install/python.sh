#!/usr/bin/env bash
# install/python.sh - install uv and Python CLI tools
#
# Strategy:
#   - Homebrew python@3.14 provides dev headers (Python.h, libpython3.14.so)
#     and satisfies brew formula deps (vim, imagemagick, etc.)
#   - uv tool install gives each CLI tool (ipython, jupyter, etc.) its own
#     isolated venv — no monolithic user-level environment to rot.
#   - Per-project venvs via `uv init` / `uv sync` for actual library work.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Python (uv)"

### uv ###

# Check the install location ($ARCH_BIN/uv), NOT just `has uv`. A stray
# ~/.local/bin/uv from before this dotfiles repo was on PLAT (or in the
# wrong PATH slot) would otherwise short-circuit the install AND break
# `uv self update`, which compares argv[0] against the recorded install dir.
if [[ -x "$ARCH_BIN/uv" ]]; then
    log_okay "uv already installed: $("$ARCH_BIN/uv" --version)"
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        log_info "Self-updating uv..."
        if ! run_logged "$ARCH_BIN/uv" self update; then
            # `uv self update` only works for standalone-installer builds; a uv
            # from another source (Homebrew, pip, an older PLAT layout) refuses.
            # Re-run the standalone installer — it replaces the binary in place,
            # so this upgrade lands AND future self-updates work.
            log_info "uv self update unsupported for this build — reinstalling via standalone installer"
            UV_INSTALL_DIR="$ARCH_BIN" run_logged bash <(curl -LsSf https://astral.sh/uv/install.sh) \
                && log_okay "uv reinstalled: $("$ARCH_BIN/uv" --version)" \
                || log_warn "uv reinstall failed — staying on $("$ARCH_BIN/uv" --version 2>/dev/null)"
        fi
    fi
else
    log_info "Installing uv → $ARCH_BIN"
    ensure_dir "$ARCH_BIN"
    # UV_INSTALL_DIR redirects the compiled uv+uvx binaries to our install bin.
    UV_INSTALL_DIR="$ARCH_BIN" run_logged bash <(curl -LsSf https://astral.sh/uv/install.sh)
    export PATH="$ARCH_BIN:$PATH"
    log_okay "Installed: $("$ARCH_BIN/uv" --version)"
fi

### CLI tools ###
#
# Each selected tool is installed via `uv tool install`, giving it an
# isolated venv under $LOCAL_PLAT/uv/tools/ with its entrypoint in $ARCH_BIN.
# UV_TOOL_BIN_DIR and UV_TOOL_DIR are set by _lib.sh.

if [[ ! -f "$DF_PACKAGES/pip.txt" ]]; then
    log_warn "No pip.txt at $DF_PACKAGES/pip.txt — skipping"
    exit 0
fi

log_info "Installing CLI tools for the $DF_PROFILE profile"
_installed=0
_skipped=0
_failed=0

while IFS= read -r _pip_file; do
    while IFS= read -r _line; do
        # Extract optional # python=X.Y constraint before stripping comments
        _py_ver="$(echo "$_line" | grep -oE 'python=[0-9]+\.[0-9]+' | cut -d= -f2 || true)"
        # Extract optional # macos-only marker
        _macos_only="$(echo "$_line" | grep -c 'macos-only' || true)"
        _pkg="$(echo "$_line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$_pkg" ]] && continue

        if [[ "$_macos_only" -gt 0 && "$OS" != "darwin" ]]; then
            log_debug "Skipping macOS-only package on $OS: $_pkg"
            (( _skipped++ )) || true
            continue
        fi

        # Keep the command array non-empty: macOS system Bash treats an empty
        # array expansion as unbound under `set -u`.
        _uv_cmd=(uv tool install "$_pkg")
        [[ -n "$_py_ver" ]] && _uv_cmd+=(--python "$_py_ver")

        if uv tool list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$_pkg "; then
            log_debug "Already installed: $_pkg"
            (( _skipped++ )) || true
        else
            if "${_uv_cmd[@]}" 2>&1; then
                (( _installed++ )) || true
            else
                log_warn "Failed to install: $_pkg"
                (( _failed++ )) || true
            fi
        fi
    done < "$_pip_file"
done < <(profile_package_files "pip.txt")

log_okay "Python tools: $_installed installed, $_skipped already present, $_failed failed"

if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Upgrading all uv tools to latest..."
    run_logged uv tool upgrade --all || log_warn "uv tool upgrade --all reported failures"
fi
