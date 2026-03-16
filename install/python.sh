#!/usr/bin/env bash
# install/python.sh - install uv and create ~/.venv with pip.txt packages
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

### venv ###

# VENV is set by _lib.sh to ~/.local/$PLAT/venv

if [[ -d "$VENV" ]]; then
    log_okay "~/.venv already exists"
else
    log_info "Creating ~/.venv (Python 3.14)"
    # --python 3.14: pin version for reproducibility across machines sharing an NFS home.
    # --seed: pre-install pip + setuptools into the venv.
    # Without it, uv creates a bare venv with no pip, which breaks `pip install`
    # and tools that expect pip to exist (e.g. some build systems).
    run_logged uv venv "$VENV" --python 3.14 --seed
    log_okay "~/.venv created"
fi

### packages ###

PIP_TXT="$DF_PACKAGES/pip.txt"
[[ -f "$PIP_TXT" ]] || { log_warn "No pip.txt at $PIP_TXT — skipping"; exit 0; }

log_info "Syncing packages from pip.txt"
# --python $VENV/bin/python: explicit path so uv targets the PLAT venv even when
# another Python is active (e.g. if the system python is higher on PATH).
# -r: single resolution pass — faster and catches inter-package conflicts that
# the old one-by-one loop let slip through.
if run_logged uv pip install --python "$VENV/bin/python" -r "$PIP_TXT"; then
    log_okay "Python packages installed"
else
    log_warn "Python packages: one or more packages failed to install"
fi
