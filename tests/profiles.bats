#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "core profile selects only the base Python manifest" {
    run env DF_PROFILE=core bash -c \
        'source "$1/install/_lib.sh"; profile_package_files pip.txt' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "$REPO/packages/pip.txt" ]
}

@test "full profile adds the disjoint full Python manifest" {
    run env DF_PROFILE=full bash -c \
        'source "$1/install/_lib.sh"; profile_package_files pip.txt' _ "$REPO"

    [ "$status" -eq 0 ]
    [[ "$output" == *"$REPO/packages/pip.txt"* ]]
    [[ "$output" == *"$REPO/packages/pip-full.txt"* ]]
}

@test "unknown profile fails before installation" {
    run env DF_PROFILE=unknown bash -c 'source "$1/install/_lib.sh"' _ "$REPO"

    [ "$status" -eq 1 ]
    [[ "$output" == *"DF_PROFILE must be 'core' or 'full'"* ]]
}

@test "core profile keeps Rust but skips optional cargo tools" {
    grep -q 'DF_PROFILE.*== "core"' "$REPO/install/rust.sh"
    grep -q 'skipping optional cargo.txt tools' "$REPO/install/rust.sh"
}
