#!/usr/bin/env bash
# install/rust.sh - install rustup + cargo tools from cargo.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

log_section "Rust"

### rustup ###

if has rustup; then
    log_ok "rustup already installed ($(rustup --version 2>&1 | head -1))"
    rustup update stable --no-self-update
else
    log_info "Installing rustup"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    log_ok "rustup installed"
fi

# Ensure cargo is in PATH for this session
export PATH="$HOME/.cargo/bin:$PATH"

### cargo tools ###

CARGO_TXT="$(dirname "$SCRIPT_DIR")/packages/cargo.txt"
if [ ! -f "$CARGO_TXT" ]; then
    log_warn "No cargo.txt found at $CARGO_TXT"
    exit 0
fi

log_info "Installing cargo tools from cargo.txt"

while IFS= read -r line; do
    # Skip blank lines and comments
    case "$line" in
        ''|\#*) continue ;;
    esac
    pkg="${line%% *}"  # first word only
    log_info "  cargo install $pkg"
    cargo install "$pkg" 2>&1 | tail -1
done < "$CARGO_TXT"

log_ok "Rust tools installed"
