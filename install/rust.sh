#!/usr/bin/env bash
# install/rust.sh - install rustup + cargo tools from cargo.txt
#
# macOS: uses Homebrew's rustup (code-signed, avoids macOS linker sandbox restrictions)
# Linux: downloads rustup-init directly from sh.rustup.rs (no Homebrew)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Rust"

# RUSTUP_HOME and CARGO_HOME are set by _lib.sh to ~/.local/$PLAT/rustup and ~/.local/$PLAT/cargo

### rustup ###

if [[ "$OS" == "darwin" ]]; then
    # macOS: Homebrew's rustup is code-signed, which is required for the macOS
    # linker to open compiled object files (com.apple.provenance enforcement).
    RUSTUP_INIT="/opt/homebrew/bin/rustup-init"
    RUSTUP_BIN="/opt/homebrew/bin/rustup"

    if [[ ! -x "$RUSTUP_BIN" ]]; then
        log_warn "Homebrew rustup not found — run install/homebrew.sh first"
        exit 1
    fi

    if [[ -x "$CARGO_HOME/bin/rustc" ]]; then
        log_okay "Rust toolchain already in PLAT dir: $("$CARGO_HOME/bin/rustc" --version 2>/dev/null)"
        log_info "Updating stable toolchain"
        run_logged "$RUSTUP_BIN" update stable --no-self-update
    else
        log_info "Initializing Rust toolchain (Homebrew rustup) → $RUSTUP_HOME"
        run_logged "$RUSTUP_INIT" -y --no-modify-path --default-toolchain stable
        log_okay "rustup initialized"
    fi
else
    # Linux: install rustup-init directly — Homebrew not available or not needed
    if [[ -x "$CARGO_HOME/bin/rustup" ]]; then
        log_okay "rustup already installed: $("$CARGO_HOME/bin/rustup" --version 2>&1)"
        log_info "Updating stable toolchain"
        run_logged "$CARGO_HOME/bin/rustup" update stable --no-self-update
    else
        log_info "Installing rustup → $CARGO_HOME/bin"
        ensure_dir "$CARGO_HOME/bin"
        _rustup_script="$(mktemp)"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$_rustup_script"
        run_logged bash "$_rustup_script" -y --no-modify-path --default-toolchain stable
        rm -f "$_rustup_script"
        log_okay "rustup installed"
    fi
fi

# Ensure cargo is on PATH for this session
export PATH="$CARGO_HOME/bin:$PATH"

### cargo-binstall ###
# cargo-binstall downloads pre-compiled binaries from GitHub releases when available,
# falling back to `cargo install` (source compilation) otherwise.
# This avoids slow compilation for common tools and works around macOS linker
# sandbox restrictions in restricted shell environments.

if cargo binstall -V &>/dev/null 2>&1; then
    log_okay "cargo-binstall already installed: $(cargo binstall -V 2>/dev/null)"
else
    log_info "Installing cargo-binstall (pre-built binary)"
    # Official installer: downloads a pre-built binary, no compilation needed
    run_logged bash <(curl -L --proto '=https' --tlsv1.2 -sSf \
        https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh)
    log_okay "cargo-binstall installed"
fi

### cargo tools ###

CARGO_TXT="$DF_PACKAGES/cargo.txt"
[[ -f "$CARGO_TXT" ]] || { log_warn "No cargo.txt at $CARGO_TXT — skipping"; exit 0; }

log_info "Installing/upgrading cargo tools from cargo.txt"

# cargo binstall handles idempotency: skips if already at latest version,
# upgrades if a newer release exists, installs if missing.
# Falls back to source compilation if no pre-built binary is available.
_ok=0 _fail=0

while IFS= read -r pkg; do
    log_info "  binstall $pkg"
    if run_logged cargo binstall --no-confirm --log-level warn "$pkg" \
        || run_logged cargo install "$pkg"; then
        log_okay "  ok    $pkg"
        (( _ok++ )) || true
    else
        log_warn "  fail  $pkg"
        (( _fail++ )) || true
    fi
done < <(_read_package_list "$CARGO_TXT")

log_okay "cargo tools: ${_ok} ok, ${_fail} failed"
