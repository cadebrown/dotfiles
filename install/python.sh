#!/usr/bin/env bash
# install/python.sh - install uv and create ~/.venv with pip.txt packages
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Python (uv)"

### uv ###

if has uv; then
    log_ok "uv already installed: $(uv --version)"
else
    log_info "Installing uv → $ARCH_BIN"
    ensure_dir "$ARCH_BIN"
    # UV_INSTALL_DIR redirects the compiled uv+uvx binaries to our PLAT-specific bin
    UV_INSTALL_DIR="$ARCH_BIN" run_logged bash <(curl -LsSf https://astral.sh/uv/install.sh)
    export PATH="$ARCH_BIN:$PATH"
    log_ok "Installed: $(uv --version)"
fi

### venv ###

# VENV is set by _lib.sh to ~/.local/$PLAT/venv

if [[ -d "$VENV" ]]; then
    log_ok "~/.venv already exists"
else
    log_info "Creating ~/.venv"
    # --seed: pre-install pip + setuptools into the venv.
    # Without it, uv creates a bare venv with no pip, which breaks `pip install`
    # and tools that expect pip to exist (e.g. some build systems).
    run_logged uv venv "$VENV" --seed
    log_ok "~/.venv created"
fi

### packages ###

PIP_TXT="$PACKAGES_DIR/pip.txt"
[[ -f "$PIP_TXT" ]] || { log_warn "No pip.txt at $PIP_TXT — skipping"; exit 0; }

log_info "Syncing packages from pip.txt"
# --python $VENV/bin/python: explicit path so uv targets the PLAT venv even when
# another Python is active (e.g. if the system python is higher on PATH).
run_logged uv pip install --python "$VENV/bin/python" -r "$PIP_TXT"
log_ok "Python packages up to date"
