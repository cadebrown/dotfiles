#!/usr/bin/env bats
# tests/paths.bats - verify all PLAT-specific tools landed in the right place
#
# The critical invariant: every compiled binary lives under ~/.local/$PLAT/
# so that machines sharing an NFS home directory don't clobber each other.

setup() {
    PLAT="$(uname -m)-$(uname -s)"
    LOCAL_PLAT="$HOME/.local/$PLAT"
}

# --- PLAT sanity ---

@test "PLAT has the expected format (arch-OS)" {
    [[ "$PLAT" =~ ^[a-zA-Z0-9_]+-[a-zA-Z]+$ ]]
}

@test "PLAT matches uname output" {
    expected="$(uname -m)-$(uname -s)"
    [[ "$PLAT" == "$expected" ]]
}

# --- chezmoi ---

@test "chezmoi is in PLAT bin" {
    [[ -x "$LOCAL_PLAT/bin/chezmoi" ]]
}

@test "chezmoi is not in arch-neutral ~/.local/bin" {
    [[ ! -f "$HOME/.local/bin/chezmoi" ]]
}

# --- uv ---

@test "uv is in PLAT bin" {
    [[ -x "$LOCAL_PLAT/bin/uv" ]]
}

@test "uvx is in PLAT bin" {
    [[ -x "$LOCAL_PLAT/bin/uvx" ]]
}

@test "uv is not in arch-neutral ~/.local/bin" {
    [[ ! -f "$HOME/.local/bin/uv" ]]
}

# --- uv data dirs ---

@test "uv tool dir is under PLAT" {
    [[ -d "$LOCAL_PLAT/uv/tools" || "$UV_TOOL_DIR" == "$LOCAL_PLAT/uv/tools" ]]
}

@test "uv python dir is under PLAT" {
    # Dir may not exist yet if no Python was downloaded, but the env var must point there
    [[ "$UV_PYTHON_INSTALL_DIR" == "$LOCAL_PLAT/uv/python" ]]
}

# --- Node (nvm) ---

@test "NVM_DIR is under PLAT" {
    [[ "$NVM_DIR" == "$LOCAL_PLAT/nvm" ]]
}

@test "nvm.sh exists at NVM_DIR" {
    [[ -s "$NVM_DIR/nvm.sh" ]]
}

@test "node is installed under NVM_DIR" {
    # node binary lives at NVM_DIR/versions/node/<ver>/bin/node
    local found
    found="$(find "$NVM_DIR/versions" -name "node" -type f 2>/dev/null | head -1)"
    [[ -x "$found" ]]
}

@test "nvm is NOT installed at legacy ~/.nvm path" {
    [[ ! -d "$HOME/.nvm" ]]
}

# --- Rust ---

@test "RUSTUP_HOME is under PLAT" {
    [[ "$RUSTUP_HOME" == "$LOCAL_PLAT/rustup" ]]
}

@test "CARGO_HOME is under PLAT" {
    [[ "$CARGO_HOME" == "$LOCAL_PLAT/cargo" ]]
}

@test "rustup toolchain exists under RUSTUP_HOME" {
    [[ -d "$RUSTUP_HOME/toolchains" ]]
}

@test "cargo bin dir exists under CARGO_HOME" {
    [[ -d "$CARGO_HOME/bin" ]]
}

@test "rust is NOT installed at legacy ~/.rustup path" {
    [[ ! -d "$HOME/.rustup" ]]
}

@test "rust is NOT installed at legacy ~/.cargo path" {
    [[ ! -d "$HOME/.cargo" ]]
}

# --- Python (venv) ---

@test "venv is under PLAT" {
    [[ -d "$LOCAL_PLAT/venv" ]]
}

@test "venv has a working python binary" {
    [[ -x "$LOCAL_PLAT/venv/bin/python" ]]
}

@test "venv is NOT at legacy ~/.venv path" {
    [[ ! -d "$HOME/.venv" ]]
}
