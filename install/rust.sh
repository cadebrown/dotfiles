#!/usr/bin/env bash
# install/rust.sh - install rustup + cargo tools from cargo.txt
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Rust"

# RUSTUP_HOME and CARGO_HOME are set by _lib.sh to ~/.local/$PLAT/rustup and ~/.local/$PLAT/cargo

### rustup ###

if has rustup; then
    log_ok "rustup already installed: $(rustup --version 2>&1)"
    log_info "Updating stable toolchain"
    run_logged rustup update stable --no-self-update
else
    log_info "Installing rustup"
    run_logged bash <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) \
        -y --no-modify-path
    log_ok "rustup installed"
fi

# Ensure cargo is on PATH for this session
export PATH="$CARGO_HOME/bin:$PATH"

### cargo tools ###

CARGO_TXT="$PACKAGES_DIR/cargo.txt"
[[ -f "$CARGO_TXT" ]] || { log_warn "No cargo.txt at $CARGO_TXT — skipping"; exit 0; }

# Build a set of already-installed tools to avoid redundant recompiles
declare -A _installed
while IFS= read -r line; do
    pkg="${line%% *}"
    _installed["$pkg"]=1
done < <(cargo install --list 2>/dev/null | grep -E '^[a-z]' | awk '{print $1}')

log_info "Installing cargo tools from cargo.txt"

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    # Skip blank lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    pkg="${line%% *}"

    if [[ -n "${_installed[$pkg]:-}" ]]; then
        log_info "  skip  $pkg (already installed)"
        (( _skip++ )) || true
        continue
    fi

    log_info "  install $pkg"
    if run_logged cargo install "$pkg"; then
        log_ok "  ok    $pkg"
        (( _ok++ )) || true
    else
        log_warn "  fail  $pkg"
        (( _fail++ )) || true
    fi
done < "$CARGO_TXT"

log_ok "cargo tools: ${_ok} installed, ${_skip} already up to date, ${_fail} failed"
