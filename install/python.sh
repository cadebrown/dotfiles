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
    log_info "Creating ~/.venv"
    # --seed: pre-install pip + setuptools into the venv.
    # Without it, uv creates a bare venv with no pip, which breaks `pip install`
    # and tools that expect pip to exist (e.g. some build systems).
    run_logged uv venv "$VENV" --seed
    log_okay "~/.venv created"
fi

### packages ###

PIP_TXT="$DF_PACKAGES/pip.txt"
[[ -f "$PIP_TXT" ]] || { log_warn "No pip.txt at $PIP_TXT — skipping"; exit 0; }

log_info "Syncing packages from pip.txt"
# --python $VENV/bin/python: explicit path so uv targets the PLAT venv even when
# another Python is active (e.g. if the system python is higher on PATH).
_ok=0 _fail=0
while IFS= read -r pkg; do
    if run_logged uv pip install --python "$VENV/bin/python" "$pkg"; then
        log_okay "  ok    $pkg"
        (( _ok++ )) || true
    else
        log_warn "  fail  $pkg"
        (( _fail++ )) || true
    fi
done < <(_read_package_list "$PIP_TXT")

if [[ $_fail -eq 0 ]]; then
    log_okay "Python packages: ${_ok} ok"
else
    log_warn "Python packages: ${_ok} ok, ${_fail} failed"
fi
