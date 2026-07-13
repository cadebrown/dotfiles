#!/usr/bin/env bats
# tests/rust-glibc-smoke.bats — _glibc_broken_bins (install/rust.sh) detects
# prebuilts the dynamic loader rejects (gnu binaries built against a newer
# glibc than the host provides — atuin/xan/yazi on Ubuntu 22.04, July 2026).
#
# The helper reads $CARGO_HOME/.crates2.json for the crate→bins mapping and
# smoke-runs each bin; a GLIBC_/libc.so signature on stderr marks it broken.
# Fixtures fake both sides: a registry with four crates, and stub bins that
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
    "mixed 1.0.0 (registry+https://github.com/rust-lang/crates.io-index)": { "bins": ["goodbin", "badbin"] }
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
    chmod +x "$FAKE_CARGO/bin/goodbin" "$FAKE_CARGO/bin/badbin" "$FAKE_CARGO/bin/yazi"
}

# Run _glibc_broken_bins for one crate against the fake CARGO_HOME.
_probe() {
    bash -c '
        source "'"$REPO_ROOT"'/install/rust.sh"
        CARGO_HOME="'"$FAKE_CARGO"'"
        _glibc_broken_bins "$1"
    ' _ "$1"
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
