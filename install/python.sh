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

if has uv; then
    log_okay "uv already installed: $(uv --version)"
else
    log_info "Installing uv → $ARCH_BIN"
    ensure_dir "$ARCH_BIN"
    # UV_INSTALL_DIR redirects the compiled uv+uvx binaries to our PLAT-specific bin
    UV_INSTALL_DIR="$ARCH_BIN" run_logged bash <(curl -LsSf https://astral.sh/uv/install.sh)
    export PATH="$ARCH_BIN:$PATH"
    log_okay "Installed: $(uv --version)"
fi

### CLI tools ###
#
# Each tool from pip.txt is installed via `uv tool install`, giving it an
# isolated venv under $LOCAL_PLAT/uv/tools/ with its entrypoint in $ARCH_BIN.
# UV_TOOL_BIN_DIR and UV_TOOL_DIR are set by _lib.sh.

PIP_TXT="$DF_PACKAGES/pip.txt"
[[ -f "$PIP_TXT" ]] || { log_warn "No pip.txt at $PIP_TXT — skipping"; exit 0; }

log_info "Installing CLI tools from pip.txt"
_installed=0
_skipped=0
_failed=0

while IFS= read -r _line; do
    # Extract optional # python=X.Y constraint before stripping comments
    _py_ver="$(echo "$_line" | grep -oE 'python=[0-9]+\.[0-9]+' | cut -d= -f2 || true)"
    _pkg="$(echo "$_line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$_pkg" ]] && continue

    _uv_args=()
    [[ -n "$_py_ver" ]] && _uv_args=(--python "$_py_ver")

    if uv tool list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$_pkg "; then
        log_debug "Already installed: $_pkg"
        (( _skipped++ )) || true
    else
        if uv tool install "$_pkg" "${_uv_args[@]}" 2>&1; then
            (( _installed++ )) || true
        else
            log_warn "Failed to install: $_pkg"
            (( _failed++ )) || true
        fi
    fi
done < "$PIP_TXT"

log_okay "Python tools: $_installed installed, $_skipped already present, $_failed failed"
