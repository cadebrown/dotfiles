#!/usr/bin/env bats
# tests/plat.bats - verify PLAT detection logic
#
# PLAT, LOCAL_PLAT, etc. are inherited from entrypoint.sh (which sources _lib.sh).

# --- PLAT format ---

@test "PLAT is non-empty" {
    [[ -n "$PLAT" ]]
}

@test "PLAT matches format plat_OS_target" {
    [[ "$PLAT" =~ ^plat_(Linux|Darwin)_[a-zA-Z0-9_-]+$ ]]
}

@test "PLAT OS component matches uname" {
    local _os
    _os="$(uname -s)"
    [[ "$PLAT" == plat_${_os}_* ]]
}

# --- LOCAL_PLAT ---

@test "LOCAL_PLAT is set and non-empty" {
    [[ -n "$LOCAL_PLAT" ]]
}

@test "LOCAL_PLAT ends with PLAT" {
    [[ "$LOCAL_PLAT" == *"$PLAT" ]]
}

@test "LOCAL_PLAT directory exists" {
    [[ -d "$LOCAL_PLAT" ]]
}

# --- PLAT check scripts ---

@test "PLAT check script exists for detected PLAT" {
    local _check="$HOME/dotfiles/install/plat/$PLAT/.plat_check.sh"
    [[ -f "$_check" ]]
}

@test "PLAT check script passes on this machine" {
    local _check="$HOME/dotfiles/install/plat/$PLAT/.plat_check.sh"
    run /bin/sh "$_check"
    [ "$status" -eq 0 ]
}

# --- _lib.sh exported vars ---

@test "OS is exported (darwin or linux)" {
    [[ "$OS" == "darwin" || "$OS" == "linux" ]]
}

@test "ARCH is exported (x86_64 or aarch64)" {
    [[ "$ARCH" == "x86_64" || "$ARCH" == "aarch64" ]]
}

@test "DF_ROOT is exported and points to dotfiles repo" {
    [[ -n "$DF_ROOT" ]]
    [[ -f "$DF_ROOT/bootstrap.sh" ]]
}

@test "DF_PACKAGES is exported and points to packages dir" {
    [[ -n "$DF_PACKAGES" ]]
    [[ -f "$DF_PACKAGES/Brewfile" ]]
}
