#!/usr/bin/env bats
# tests/rust-glibc-smoke.bats — _loader_broken_bins (install/rust.sh) detects
# prebuilts the dynamic loader rejects.
#
# The helper reads $CARGO_HOME/.crates2.json for the crate→bins mapping and
# smoke-runs each bin; a loader error on stderr marks it broken. Fixtures fake
# both sides: a registry with five crates, and stub bins that
# either succeed or replay the real ld.so error (exit 127).
#
# Runs locally with brew-installed bats-core, and inside tests/run.sh docker.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_CARGO="$BATS_TEST_TMPDIR/cargo"
    mkdir -p "$FAKE_CARGO/bin"

    cat > "$FAKE_CARGO/.crates2.json" <<'EOF'
{
  "installs": {
    "goodcrate 1.0.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["goodbin"] },
    "badcrate 18.17.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["badbin"] },
    "yazi-fm 26.5.6 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["yazi"] },
    "mixed 1.0.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["goodbin", "badbin"] },
    "missinglib 1.0.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["missinglib"] },
    "exitsbad 1.0.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["exitsbad"] },
    "hangs 1.0.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["hangs"] }
  }
}
EOF

    cat > "$FAKE_CARGO/bin/goodbin" <<'EOF'
#!/bin/sh
echo "goodbin 1.0.0"
EOF
    # Replays the real dynamic-loader failure: message on stderr, exit 127.
    cat > "$FAKE_CARGO/bin/badbin" <<'EOF'
#!/bin/sh
echo "badbin: /lib/x86_64-linux-gnu/libc.so.6: version \`GLIBC_2.39' not found (required by badbin)" >&2
exit 127
EOF
    cp "$FAKE_CARGO/bin/badbin" "$FAKE_CARGO/bin/yazi"
    cat > "$FAKE_CARGO/bin/missinglib" <<'EOF'
#!/bin/sh
echo "missinglib: error while loading shared libraries: libgit2.so.1.9: cannot open shared object file: No such file or directory" >&2
exit 127
EOF
    cat > "$FAKE_CARGO/bin/exitsbad" <<'EOF'
#!/bin/sh
exit 1
EOF
    cat > "$FAKE_CARGO/bin/hangs" <<'EOF'
#!/bin/sh
trap '' TERM
while :; do :; done
EOF
    chmod +x "$FAKE_CARGO/bin/goodbin" "$FAKE_CARGO/bin/badbin" \
        "$FAKE_CARGO/bin/yazi" "$FAKE_CARGO/bin/missinglib" \
        "$FAKE_CARGO/bin/exitsbad" "$FAKE_CARGO/bin/hangs"
}

# Run _loader_broken_bins for one crate against the fake CARGO_HOME.
_probe() {
    bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        CARGO_HOME="'"$FAKE_CARGO"'"
        _loader_broken_bins "$1"
    ' _ "$1"
}

@test "flags a bin with a missing shared library" {
    run _probe missinglib
    [ "$status" -eq 0 ]
    [ "$output" = "missinglib" ]
}

@test "does not confuse a generic nonzero exit with a loader failure" {
    run _probe exitsbad
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "kills a hanging probe without calling the installed tool broken" {
    DF_TOOL_SMOKE_TIMEOUT=0.1 run _probe hangs
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "does not confuse ripgrep-all usage errors with loader failures" {
    run bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        ! _cargo_loader_error "Error: no filename"
        ! _cargo_loader_error "inappropriate ioctl for device"
    '
    [ "$status" -eq 0 ]
}

@test "flags a bin the loader rejects" {
    run _probe badcrate
    [ "$status" -eq 0 ]
    [ "$output" = "badbin" ]
}

@test "passes a healthy bin" {
    run _probe goodcrate
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "maps crate name to differing bin name (yazi-fm → yazi)" {
    run _probe yazi-fm
    [ "$status" -eq 0 ]
    [ "$output" = "yazi" ]
}

@test "flags only the broken bin of a multi-bin crate" {
    run _probe mixed
    [ "$status" -eq 0 ]
    [ "$output" = "badbin" ]
}

@test "unknown crate yields nothing, exit 0" {
    run _probe nosuchcrate
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "missing registry yields nothing, exit 0" {
    rm "$FAKE_CARGO/.crates2.json"
    run _probe badcrate
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "cargo entrypoint validation rejects a missing executable" {
    rm "$FAKE_CARGO/bin/goodbin"
    run bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        CARGO_HOME="'"$FAKE_CARGO"'"
        _missing_cargo_bins goodcrate
    '
    [ "$status" -eq 0 ]
    [ "$output" = "goodbin" ]
}

@test "cargo entrypoint validation rejects a missing receipt" {
    run bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        CARGO_HOME="'"$FAKE_CARGO"'"
        _missing_cargo_bins unknowncrate
    '
    [ "$status" -eq 0 ]
    [ "$output" = "<receipt>" ]
}

@test "binstall never compiles a musl target internally" {
    grep -q -- '--disable-strategies compile' "$REPO_ROOT/install/rust.sh"
    grep -q 'DF_CARGO_STRATEGIES:-.*== "compile"' "$REPO_ROOT/install/rust.sh"
}

@test "rust-docs-mcp source builds vendor libgit2" {
    run bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        brew() { return 1; }
        run_logged() { printf "%s\\n" "$*"; }
        _source_install_crate rust-docs-mcp --force
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"env LIBGIT2_NO_PKG_CONFIG=1 cargo install --locked --force rust-docs-mcp"* ]]
}

# Execute a stub Cargo process so these checks observe the child's environment,
# including whether an OpenSSL selection leaks into subsequent shell commands.
_source_probe() {
    local openssl_prefix="$BATS_TEST_TMPDIR/brew prefix/opt/openssl@3"
    mkdir -p "$openssl_prefix/include/openssl" "$openssl_prefix/lib"
    touch "$openssl_prefix/include/openssl/ssl.h"
    cat > "$FAKE_CARGO/bin/cargo" <<'EOF'
#!/usr/bin/env bash
printf 'OPENSSL_DIR=%s\n' "${OPENSSL_DIR-unset}"
printf 'OPENSSL_INCLUDE_DIR=%s\n' "${OPENSSL_INCLUDE_DIR-unset}"
printf 'X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR=%s\n' "${X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR-unset}"
printf 'LIBGIT2_NO_PKG_CONFIG=%s\n' "${LIBGIT2_NO_PKG_CONFIG-unset}"
printf 'CARGO_ENCODED_RUSTFLAGS=%s\n' "${CARGO_ENCODED_RUSTFLAGS-unset}"
printf 'cargo args: %s\n' "$*"
exit "${PROBE_EXIT:-0}"
EOF
    chmod +x "$FAKE_CARGO/bin/cargo"
    bash -c '
        source "$1/install/rust.sh"
        export PATH="$2/bin:$PATH"
        unset OPENSSL_DIR OPENSSL_LIB_DIR OPENSSL_INCLUDE_DIR LIBGIT2_NO_PKG_CONFIG
        unset X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR
        unset CARGO_ENCODED_RUSTFLAGS
        export RUSTFLAGS=$'"'"'-C target-cpu=x86-64-v3\n-C debuginfo=1'"'"'
        OS=linux
        brew() {
            [[ "$*" == "--prefix openssl@3" ]] || return 99
            printf "%s\n" "$openssl_prefix"
        }
        openssl_prefix="$3"
        case "$4" in
            explicit) export OPENSSL_DIR=/custom/openssl ;;
            split) export OPENSSL_INCLUDE_DIR=/custom/include ;;
            target) export X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR=/target/openssl ;;
            missing) openssl_prefix="$3/missing" ;;
            no-brew) brew() { return 1; } ;;
            failure) export PROBE_EXIT=42 ;;
            encoded) export CARGO_ENCODED_RUSTFLAGS=$'"'"'-C\x1fopt-level=2'"'"' ;;
            encoded-empty) export CARGO_ENCODED_RUSTFLAGS= ;;
            macos) OS=darwin ;;
        esac
        run_logged() { "$@"; }
        _source_install_crate "$5" --force
        printf "parent OPENSSL_DIR=%s\n" "${OPENSSL_DIR-unset}"
        printf "parent CARGO_ENCODED_RUSTFLAGS=%s\n" "${CARGO_ENCODED_RUSTFLAGS-unset}"
    ' _ "$REPO_ROOT" "$FAKE_CARGO" "$openssl_prefix" "$1" "${2:-rust-docs-mcp}"
}

@test "source builds select installed Homebrew OpenSSL 3 only for the Cargo process" {
    run _source_probe default
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPENSSL_DIR=$BATS_TEST_TMPDIR/brew prefix/opt/openssl@3"* ]]
    [[ "$output" == *"LIBGIT2_NO_PKG_CONFIG=1"* ]]
    [[ "$output" == *"cargo args: install --locked --force rust-docs-mcp"* ]]
    [[ "$output" == *"parent OPENSSL_DIR=unset"* ]]
    [[ "$output" == *$'CARGO_ENCODED_RUSTFLAGS=-C\x1ftarget-cpu=x86-64-v3\x1f-C\x1fdebuginfo=1\x1f-Clink-arg=-Wl,-rpath,'"$BATS_TEST_TMPDIR/brew prefix/opt/openssl@3/lib"* ]]
    [[ "$output" == *"parent CARGO_ENCODED_RUSTFLAGS=unset"* ]]
}

@test "source build rpath preserves encoded flags precedence including empty flags" {
    run _source_probe encoded
    [ "$status" -eq 0 ]
    [[ "$output" == *$'CARGO_ENCODED_RUSTFLAGS=-C\x1fopt-level=2\x1f-Clink-arg=-Wl,-rpath,'* ]]
    [[ "$output" != *"target-cpu="* ]]
    run _source_probe encoded-empty
    [ "$status" -eq 0 ]
    [[ "$output" == *"CARGO_ENCODED_RUSTFLAGS=-Clink-arg=-Wl,-rpath,"* ]]
    [[ "$output" != *"target-cpu="* ]]
}

@test "macOS source builds select OpenSSL without Linux rpath flags" {
    run _source_probe macos
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPENSSL_DIR=$BATS_TEST_TMPDIR/brew prefix/opt/openssl@3"* ]]
    [[ "$output" == *"CARGO_ENCODED_RUSTFLAGS=unset"* ]]
}

@test "other source crates select OpenSSL 3 without changing libgit2 policy" {
    run _source_probe default another-crate
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPENSSL_DIR=$BATS_TEST_TMPDIR/brew prefix/opt/openssl@3"* ]]
    [[ "$output" == *"LIBGIT2_NO_PKG_CONFIG=unset"* ]]
}

@test "source builds preserve explicit global split and target OpenSSL paths" {
    for override in explicit split target; do
        run _source_probe "$override"
        [ "$status" -eq 0 ]
        [[ "$output" != *"brew prefix"* ]]
        case "$override" in
            explicit) [[ "$output" == *"OPENSSL_DIR=/custom/openssl"* ]] ;;
            split) [[ "$output" == *"OPENSSL_INCLUDE_DIR=/custom/include"* ]] ;;
            target) [[ "$output" == *"X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR=/target/openssl"* ]] ;;
        esac
    done
}

@test "source builds keep normal discovery when Homebrew OpenSSL 3 is unavailable" {
    for availability in missing no-brew; do
        run _source_probe "$availability"
        [ "$status" -eq 0 ]
        [[ "$output" == *"OPENSSL_DIR=unset"* ]]
    done
}

@test "source builds propagate Cargo failure with selected OpenSSL" {
    run _source_probe failure
    [ "$status" -eq 42 ]
}

@test "rust-docs-mcp accepts only its isolated false GitHub 403 after live probes" {
    run bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        download() { printf "github" > "$2"; }
        git() { printf "deadbeef\\tHEAD\\n"; }
        _rust_docs_doctor_passed "$1"
    ' _ $'✅ Rust toolchain: ok\n✅ Nightly toolchain: ok\n✅ Rustdoc JSON: ok\n✅ Git: ok\n❌ Network: crates.io reachable (200 OK) but GitHub unreachable (403 Forbidden)\n✅ Cache directory: ok\n[ERROR] Doctor found 1 issue.'
    [ "$status" -eq 0 ]
}

@test "rust-docs-mcp does not hide another doctor failure" {
    run bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        download() { printf "github" > "$2"; }
        git() { printf "deadbeef\\tHEAD\\n"; }
        _rust_docs_doctor_passed "$1"
    ' _ $'✅ Rust toolchain: ok\n✅ Nightly toolchain: ok\n✅ Rustdoc JSON: ok\n✅ Git: ok\n❌ Network: crates.io reachable (200 OK) but GitHub unreachable (403 Forbidden)\n❌ Cache directory: broken\n[ERROR] Doctor found 2 issues.'
    [ "$status" -ne 0 ]
}
