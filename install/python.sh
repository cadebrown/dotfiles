#!/usr/bin/env sh
# install/python.sh - install uv and create ~/.venv with packages from pip.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "Python (uv)"

### uv ###

if has uv; then
    log_ok "uv already installed ($(uv --version))"
else
    log_info "Installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    log_ok "uv installed: $(uv --version)"
fi

### ~/.venv ###

VENV="$HOME/.venv"
if [ -d "$VENV" ]; then
    log_ok "~/.venv already exists"
else
    log_info "Creating ~/.venv"
    uv venv "$VENV"
    log_ok "~/.venv created"
fi

### pip packages ###

PIP_TXT="$(dirname "$SCRIPT_DIR")/packages/pip.txt"
if [ ! -f "$PIP_TXT" ]; then
    log_warn "No pip.txt found at $PIP_TXT"
    exit 0
fi

log_info "Installing Python packages from pip.txt"
uv pip install --python "$VENV/bin/python" -r "$PIP_TXT"
log_ok "Python packages installed"
