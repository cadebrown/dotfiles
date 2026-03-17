#!/usr/bin/env bats
# tests/scratch.bats - verify scratch space symlink setup
#
# These tests verify the scratch.sh script's behavior. They are
# meaningful primarily in environments where scratch space is configured.
# Tests gracefully skip when no scratch space is available.

skip_if_no_scratch() {
    [[ -n "${SCRATCH:-}" ]] || skip "No scratch space configured"
}

# --- Scratch detection ---

@test "SCRATCH is empty or a valid directory" {
    if [[ -n "${SCRATCH:-}" ]]; then
        [[ -d "$SCRATCH" ]]
    fi
}

@test "PATHS is derived from SCRATCH" {
    if [[ -n "${SCRATCH:-}" ]]; then
        [[ "$PATHS" == "$SCRATCH/.paths" ]]
    else
        [[ -z "${PATHS:-}" ]]
    fi
}

# --- Symlink integrity (only when scratch is active) ---

@test "~/.local is a symlink when scratch is configured" {
    skip_if_no_scratch
    [[ -L "$HOME/.local" ]]
}

@test "~/.local symlink target exists" {
    skip_if_no_scratch
    [[ -e "$HOME/.local" ]]
}

@test "~/.cache is a symlink when scratch is configured" {
    skip_if_no_scratch
    [[ -L "$HOME/.cache" ]]
}

@test "~/.cache symlink target exists" {
    skip_if_no_scratch
    [[ -e "$HOME/.cache" ]]
}

@test "LOCAL_PLAT resolves through scratch symlink" {
    skip_if_no_scratch
    local _resolved
    _resolved="$(readlink -f "$LOCAL_PLAT")"
    # Should resolve to a path under scratch, not under $HOME directly
    [[ "$_resolved" == "$SCRATCH"* || "$_resolved" == "$PATHS"* ]]
}

# --- scratch.sh idempotency ---

@test "scratch.sh is idempotent (second run succeeds)" {
    skip_if_no_scratch
    run bash "$HOME/dotfiles/install/scratch.sh"
    [ "$status" -eq 0 ]
}
