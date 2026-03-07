#!/usr/bin/env bats
# tests/shell.bats - verify ~/.zprofile sources cleanly and sets the right env
#
# Each test invokes a fresh zsh with --no-rcs (skips ~/.zshrc) and sources
# ~/.zprofile explicitly, then asserts on the resulting environment.
# SSH_AUTH_SOCK=1 prevents the ssh-agent block from running in the container.

# Use export to set SSH_AUTH_SOCK before sourcing — prevents the ssh-agent
# block from running (no keys in test environment). `VAR=val source` doesn't
# work reliably for zsh builtins.
ZSH_SOURCE='export SSH_AUTH_SOCK=already_running; source ~/.zprofile'

setup() {
    PLAT="$(uname -m)-$(uname -s)"
    LOCAL_PLAT="$HOME/.local/$PLAT"
}

# --- Sourcing ---

@test "zprofile sources in zsh without error" {
    run zsh --no-rcs -c "$ZSH_SOURCE"
    [ "$status" -eq 0 ]
}

@test "zprofile is idempotent (source twice, no error)" {
    run zsh --no-rcs -c "$ZSH_SOURCE; $ZSH_SOURCE"
    [ "$status" -eq 0 ]
}

# --- PLAT variables ---

@test "_PLAT is set after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$_PLAT"
    [ "$status" -eq 0 ]
    [[ "$output" == "$PLAT" ]]
}

@test "_LOCAL_PLAT points to ~/.local/\$PLAT" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$_LOCAL_PLAT"
    [ "$status" -eq 0 ]
    [[ "$output" == "$LOCAL_PLAT" ]]
}

# --- PATH ---

@test "PLAT bin is on PATH after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$PATH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$LOCAL_PLAT/bin"* ]]
}

@test "cargo bin is on PATH after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$PATH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$LOCAL_PLAT/cargo/bin"* ]]
}

# --- uv env vars ---

@test "UV_TOOL_BIN_DIR set to PLAT bin" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$UV_TOOL_BIN_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "$LOCAL_PLAT/bin" ]]
}

@test "UV_TOOL_DIR set to PLAT uv/tools" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$UV_TOOL_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "$LOCAL_PLAT/uv/tools" ]]
}

@test "UV_PYTHON_INSTALL_DIR set to PLAT uv/python" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$UV_PYTHON_INSTALL_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "$LOCAL_PLAT/uv/python" ]]
}

# --- Rust env vars ---

@test "RUSTUP_HOME set to PLAT rustup" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$RUSTUP_HOME"
    [ "$status" -eq 0 ]
    [[ "$output" == "$LOCAL_PLAT/rustup" ]]
}

@test "CARGO_HOME set to PLAT cargo" {
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$CARGO_HOME"
    [ "$status" -eq 0 ]
    [[ "$output" == "$LOCAL_PLAT/cargo" ]]
}

# --- Tool invocability ---

@test "uv is callable after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; uv --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^uv\ [0-9] ]]
}

@test "cargo is callable after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; cargo --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^cargo\ [0-9] ]]
}

@test "node is callable after sourcing zprofile (via nvm)" {
    run zsh --no-rcs -c "$ZSH_SOURCE; node --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^v[0-9] ]]
}

@test "python is callable via venv after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; python --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^Python\ 3 ]]
}
