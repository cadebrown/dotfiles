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

@test "every Python tool declares its required entrypoint contract" {
    local manifest
    for manifest in "$REPO/packages/pip.txt" "$REPO/packages/pip-full.txt"; do
        run awk '
            /^[[:space:]]*($|#)/ { next }
            !/#[[:space:]].*entry=[^[:space:]]+/ { print NR ":" $0; bad = 1 }
            END { exit bad }
        ' "$manifest"
        [ "$status" -eq 0 ]
    done
}

@test "leanblueprint validation supplies the minimal project its import requires" {
    grep -Fq 'git -C "$_project" init -q' "$REPO/install/python.sh"
    grep -Fq 'lakefile.toml' "$REPO/install/python.sh"
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
