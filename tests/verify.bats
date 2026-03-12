#!/usr/bin/env bats
# tests/verify.bats - test the verify-path.sh diagnostic tool

setup() {
    PLAT="$(uname -m)-$(uname -s)"
    LOCAL_PLAT="$HOME/.local/$PLAT"
    VERIFY="$HOME/dotfiles/install/verify-path.sh"
}

@test "verify-path.sh exists and is executable" {
    [[ -x "$VERIFY" ]]
}

@test "verify-path.sh --help exits 0" {
    run bash "$VERIFY" --help
    [ "$status" -eq 0 ]
}

@test "verify-path.sh --arch passes" {
    run bash "$VERIFY" --arch
    [ "$status" -eq 0 ]
}

@test "verify-path.sh --symlinks passes" {
    run bash "$VERIFY" --symlinks
    [ "$status" -eq 0 ]
}

@test "verify-path.sh --duplicates passes" {
    run bash "$VERIFY" --duplicates
    [ "$status" -eq 0 ]
}

@test "verify-path.sh --all passes" {
    run bash "$VERIFY" --all
    [ "$status" -eq 0 ]
}
