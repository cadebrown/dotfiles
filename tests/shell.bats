#!/usr/bin/env bats
# tests/shell.bats - verify ~/.zprofile and ~/.bash_profile source cleanly
#
# Each test invokes a fresh shell and sources the login profile, then asserts
# on the resulting environment.
# SSH_AUTH_SOCK=1 prevents the ssh-agent block from running in the container.
#
# PLAT, LOCAL_PLAT, etc. are inherited from entrypoint.sh (which sources _lib.sh).

# Use export to set SSH_AUTH_SOCK before sourcing — prevents the ssh-agent
# block from running (no keys in test environment). `VAR=val source` doesn't
# work reliably for zsh builtins.
ZSH_SOURCE='export SSH_AUTH_SOCK=already_running; source ~/.zprofile'
BASH_SOURCE_CMD='export SSH_AUTH_SOCK=already_running; source ~/.bash_profile'

# --- zsh sourcing ---

@test "zprofile sources in zsh without error" {
    run zsh --no-rcs -c "$ZSH_SOURCE"
    [ "$status" -eq 0 ]
}

@test "zprofile is idempotent (source twice, no error)" {
    run zsh --no-rcs -c "$ZSH_SOURCE; $ZSH_SOURCE"
    [ "$status" -eq 0 ]
}

# --- bash sourcing ---

@test "bash_profile sources in bash without error" {
    run bash --norc --noprofile -c "$BASH_SOURCE_CMD"
    [ "$status" -eq 0 ]
}

@test "bash_profile is idempotent (source twice, no error)" {
    run bash --norc --noprofile -c "$BASH_SOURCE_CMD; $BASH_SOURCE_CMD"
    [ "$status" -eq 0 ]
}

# --- PLAT variables (zsh) ---

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

# --- PLAT variables (bash) ---

@test "_PLAT is set after sourcing bash_profile" {
    run bash --norc --noprofile -c "$BASH_SOURCE_CMD; echo \$_PLAT"
    [ "$status" -eq 0 ]
    [[ "$output" == "$PLAT" ]]
}

@test "_LOCAL_PLAT points to ~/.local/\$PLAT (bash)" {
    run bash --norc --noprofile -c "$BASH_SOURCE_CMD; echo \$_LOCAL_PLAT"
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

@test "node is callable after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; node --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^v[0-9] ]]
}

@test "python is callable via venv after sourcing zprofile" {
    run zsh --no-rcs -c "$ZSH_SOURCE; python --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^Python\ 3 ]]
}

# --- Homebrew stability env vars ---

skip_if_not_linux() {
    [[ "$(uname -s)" == "Linux" ]] || skip "Only applies to Linux"
}

@test "HOMEBREW_NO_AUTO_UPDATE is set to 1" {
    skip_if_not_linux
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$HOMEBREW_NO_AUTO_UPDATE"
    [ "$status" -eq 0 ]
    [[ "$output" == "1" ]]
}

@test "HOMEBREW_NO_INSTALL_FROM_API is set to 1" {
    skip_if_not_linux
    run zsh --no-rcs -c "$ZSH_SOURCE; echo \$HOMEBREW_NO_INSTALL_FROM_API"
    [ "$status" -eq 0 ]
    [[ "$output" == "1" ]]
}
