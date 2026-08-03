#!/usr/bin/env bats
# tests/brew-glibc.bats — the glibc floor check in install/linux-packages.sh.
#
# Homebrew's Linux bottles carry the glibc floor of whatever builder image
# homebrew-core was using when they were poured. When the builder moves ahead of
# the installed glibc keg (Ubuntu 22.04 → 24.04 and glibc 2.35 → 2.39, Jul 2026)
# the bottles pour cleanly and then refuse to load, naming the binary rather
# than the cause. _glibc_offenders finds them by reading the GLIBC_x.y strings
# out of .dynstr — deliberately not via readelf, which is itself one of the
# binaries that stops working.
#
# grep -a treats the fixtures below as binaries, so plain text files carrying
# the same version strings stand in for real ELFs.
#
# Runs locally with brew-installed bats-core, and inside tests/run.sh docker.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURES="$BATS_TEST_TMPDIR/kegs"
    mkdir -p "$FIXTURES"

    # A bottle from the older builder: nothing beyond what glibc 2.35 defines.
    printf 'GLIBC_2.2.5\nGLIBC_2.14\nGLIBC_2.34\n' > "$FIXTURES/old-bottle"
    # A bottle from the newer builder.
    printf 'GLIBC_2.2.5\nGLIBC_2.38\n' > "$FIXTURES/new-bottle"
    # Highest wins, whatever order the strings appear in.
    printf 'GLIBC_2.39\nGLIBC_2.4\nGLIBC_2.34\n' > "$FIXTURES/unsorted"
    # GLIBC_PRIVATE has no version number and must not parse as one.
    printf 'GLIBC_PRIVATE\nGLIBC_2.34\n' > "$FIXTURES/private-only"
    # Nothing at all — static binary, shell script, data file.
    printf 'no version strings here\n' > "$FIXTURES/inert"
}

_ver_lt_probe() {
    bash -c 'source "'"$REPO_ROOT"'/install/linux-packages.sh"; _ver_lt "$1" "$2"' _ "$1" "$2"
}

_offenders() {
    local provided="$1"; shift
    local paths=("$@")
    printf '%s\0' "${paths[@]}" | bash -c '
        source "'"$REPO_ROOT"'/install/linux-packages.sh"
        _glibc_offenders "$1"
    ' _ "$provided"
}

_provided() {
    bash -c 'source "'"$REPO_ROOT"'/install/linux-packages.sh"; _glibc_provided "$1"' _ "$1"
}

@test "_ver_lt orders release versions" {
    run _ver_lt_probe 2.35 2.39
    [ "$status" -eq 0 ]
    run _ver_lt_probe 2.39 2.35
    [ "$status" -ne 0 ]
}

@test "_ver_lt is not lexical (2.9 < 2.10)" {
    run _ver_lt_probe 2.9 2.10
    [ "$status" -eq 0 ]
}

@test "_ver_lt is strict — equal versions are not less" {
    run _ver_lt_probe 2.39 2.39
    [ "$status" -ne 0 ]
}

@test "_glibc_provided reports the highest version defined" {
    run _provided "$FIXTURES/unsorted"
    [ "$status" -eq 0 ]
    [ "$output" = "GLIBC_2.39" ]
}

@test "flags a bottle needing more than the keg provides" {
    run _offenders GLIBC_2.35 "$FIXTURES/new-bottle"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\tGLIBC_2.38' "$FIXTURES/new-bottle")" ]
}

@test "passes a bottle within the keg's floor" {
    run _offenders GLIBC_2.35 "$FIXTURES/old-bottle"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "reports the highest requirement per file, not the first seen" {
    run _offenders GLIBC_2.35 "$FIXTURES/unsorted"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\tGLIBC_2.39' "$FIXTURES/unsorted")" ]
}

@test "flags only the offending file of a mixed set" {
    run _offenders GLIBC_2.35 "$FIXTURES/old-bottle" "$FIXTURES/new-bottle" "$FIXTURES/inert"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\tGLIBC_2.38' "$FIXTURES/new-bottle")" ]
}

@test "GLIBC_PRIVATE is not a version" {
    run _offenders GLIBC_2.35 "$FIXTURES/private-only"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a newer keg clears everything" {
    run _offenders GLIBC_2.39 "$FIXTURES/old-bottle" "$FIXTURES/new-bottle" "$FIXTURES/unsorted"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "empty input yields nothing, exit 0" {
    run bash -c '
        source "'"$REPO_ROOT"'/install/linux-packages.sh"
        printf "" | _glibc_offenders GLIBC_2.35
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
