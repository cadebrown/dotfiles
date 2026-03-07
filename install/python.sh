#!/usr/bin/env bash
# install/python.sh - install uv and create ~/.venv with pip.txt packages
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Python (uv)"

### uv ###

if has uv; then
    log_ok "uv already installed: $(uv --version)"
else
    log_info "Installing uv"
    run_logged bash <(curl -LsSf https://astral.sh/uv/install.sh)
    # uv installs to ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
    log_ok "Installed: $(uv --version)"
fi

### ~/.venv ###

VENV="$HOME/.venv"

if [[ -d "$VENV" ]]; then
    log_ok "~/.venv already exists"
else
    log_info "Creating ~/.venv"
    run_logged uv venv "$VENV"
    log_ok "~/.venv created"
fi

### packages ###

PIP_TXT="$PACKAGES_DIR/pip.txt"
[[ -f "$PIP_TXT" ]] || { log_warn "No pip.txt at $PIP_TXT — skipping"; exit 0; }

log_info "Syncing packages from pip.txt"
run_logged uv pip install --python "$VENV/bin/python" -r "$PIP_TXT"
log_ok "Python packages up to date"
