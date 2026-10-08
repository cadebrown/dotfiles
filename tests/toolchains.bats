#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "managed toolchain scripts parse" {
    bash -n "$REPO/install/audit-versions.sh"
    bash -n "$REPO/install/go.sh"
    bash -n "$REPO/install/julia.sh"
    bash -n "$REPO/install/quarto.sh"
}

@test "version audit emits normalized machine-readable records" {
    managed_version_fixture
    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        bash "$REPO/install/audit-versions.sh"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length >= 16' >/dev/null
    echo "$output" | jq -e 'all(.[];
        has("tool") and has("manager") and has("expected") and
        has("policy") and has("installed") and has("status") and
        has("source") and has("platform"))' >/dev/null
    echo "$output" | jq -e 'all(.[].status; . == "current" or . == "outdated" or . == "missing")' >/dev/null
    # Confirms Julia came from the fixture, never a host launcher/download path.
    [ "$(grep -cx julia "$DF_VERSION_FIXTURE_LOG")" -eq 1 ]
}

managed_version_fixture() {
    fake_home="$BATS_TEST_TMPDIR/audit-home"
    stub_bin="$BATS_TEST_TMPDIR/audit-bin"
    # The host policy may export a tools root outside HOME. Keep version probes
    # inside the fixture even when running on a configured bootstrap host.
    export DF_TOOLS_ROOT="$fake_home/.local"
    export DF_PLAT=auto
    export DF_VERSION_FIXTURE_OS="${1:-Linux}"
    unset DF_QUARTO_VERSION
    local command
    mkdir -p "$fake_home/.local/nvm" "$stub_bin"
    printf '%s\n' 'nvm() { printf "0.40.7\\n"; }' \
        > "$fake_home/.local/nvm/nvm.sh"

    cat > "$stub_bin/managed-version" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >> "$DF_VERSION_FIXTURE_LOG"
case "${0##*/}" in
    rustup)  printf 'rustup 1.29.2\n' ;;
    rustc)   printf 'rustc 1.98.0 (test)\n' ;;
    node)    printf 'v24.20.0\n' ;;
    npm)     printf '12.0.2\n' ;;
    python3) printf 'Python 3.14.7\n' ;;
    uv)      printf 'uv 0.12.9\n' ;;
    go)      printf 'go version go1.27.1 linux/arm64\n' ;;
    zig)     printf '%s\n' "${DF_VERSION_FIXTURE_ZIG:-0.17.0}" ;;
    juliaup) printf 'Juliaup 1.22.4\n' ;;
    julia)   printf 'julia version 1.12.7\n' ;;
    lean)    printf 'Lean (version 4.33.1, test)\n' ;;
    cmake)   printf 'cmake version 4.4.3\n' ;;
    ninja)   printf '1.13.2\n' ;;
    quarto)  printf '%s\n' "${DF_VERSION_FIXTURE_QUARTO:-1.10.18}" ;;
    brew)    printf 'llvm@22 22.1.8\n' ;;
esac
EOF
    chmod 755 "$stub_bin/managed-version"
    for command in rustup rustc node npm python3 uv go zig juliaup julia lean \
        cmake ninja quarto brew; do
        ln -s managed-version "$stub_bin/$command"
    done

    cat > "$stub_bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
    -s) printf '%s\n' "$DF_VERSION_FIXTURE_OS" ;;
    -m)
        case "$DF_VERSION_FIXTURE_OS" in
            Linux) printf 'aarch64\n' ;;
            Darwin) printf 'arm64\n' ;;
            *) exit 1 ;;
        esac ;;
    *) exit 1 ;;
esac
EOF
    # Avoid selecting a live host's overlay policy during an OS fixture test.
    printf '#!/bin/sh\nprintf "version-audit-fixture\\n"\n' > "$stub_bin/hostname"
    chmod 755 "$stub_bin/uname" "$stub_bin/hostname"

    # Only explicitly selected shell utilities are visible. A missing/new
    # version stub must not fall through to a host manager that can install tools.
    local utility utility_path
    local utility_bin="$BATS_TEST_TMPDIR/audit-utilities"
    mkdir -p "$utility_bin"
    for utility in bash jq dirname tr sed head awk grep cat sort tail cut \
        readlink sysctl getconf find date ls; do
        utility_path="$(command -v "$utility" || true)"
        if [[ "$utility_path" == /* ]]; then ln -s "$utility_path" "$utility_bin/$utility"; fi
    done
    fixture_path="$stub_bin:$utility_bin"
    export DF_VERSION_FIXTURE_LOG="$BATS_TEST_TMPDIR/version-commands"
}

@test "strict audit accepts unpinned releases newer than minimum floors" {
    managed_version_fixture

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '
        [.[] | select(.tool == "rustup" or .tool == "juliaup" or .tool == "zig")]
        | length == 3 and all(.[]; .policy == "minimum" and .status == "current")
    ' >/dev/null
}

@test "strict audit rejects Zig below its minimum floor" {
    managed_version_fixture

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        DF_VERSION_FIXTURE_ZIG=0.15.2 \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 1 ]
    echo "$output" | jq -e '
        [.[] | select(.status != "current")]
        | length == 1 and .[0].tool == "zig" and .[0].policy == "minimum"
          and .[0].expected == "0.16.0" and .[0].installed == "0.15.2"
          and .[0].status == "outdated"
    ' >/dev/null
}

@test "strict audit accepts macOS Quarto newer than its Homebrew minimum" {
    managed_version_fixture Darwin

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        DF_VERSION_FIXTURE_QUARTO=1.10.20 \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'any(.[]; .tool == "quarto"
        and .platform == "darwin/aarch64" and .manager == "homebrew"
        and .source == "quarto" and .policy == "minimum"
        and .expected == "1.10.18" and .installed == "1.10.20"
        and .status == "current")' >/dev/null
}

@test "strict audit rejects macOS Quarto below its Homebrew minimum" {
    managed_version_fixture Darwin

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        DF_VERSION_FIXTURE_QUARTO=1.10.17 \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 1 ]
    echo "$output" | jq -e '[.[] | select(.status != "current")]
        | length == 1 and .[0].tool == "quarto"
          and .[0].platform == "darwin/aarch64" and .[0].manager == "homebrew"
          and .[0].source == "quarto" and .[0].policy == "minimum"
          and .[0].expected == "1.10.18" and .[0].installed == "1.10.17"
          and .[0].status == "outdated"' >/dev/null
}

@test "strict audit rejects missing macOS Quarto without probing a host tool" {
    managed_version_fixture Darwin
    rm "$stub_bin/quarto"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 1 ]
    echo "$output" | jq -e '[.[] | select(.status != "current")]
        | length == 1 and .[0].tool == "quarto"
          and .[0].platform == "darwin/aarch64" and .[0].manager == "homebrew"
          and .[0].source == "quarto" and .[0].policy == "minimum"
          and .[0].expected == "1.10.18" and .[0].installed == ""
          and .[0].status == "missing"' >/dev/null
    ! grep -qx quarto "$DF_VERSION_FIXTURE_LOG"
}

@test "strict audit rejects Linux Quarto newer than its archive pin" {
    managed_version_fixture Linux

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        DF_VERSION_FIXTURE_QUARTO=1.10.20 \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 1 ]
    echo "$output" | jq -e '[.[] | select(.status != "current")]
        | length == 1 and .[0].tool == "quarto"
          and .[0].platform == "linux/aarch64" and .[0].manager == "quarto"
          and .[0].source == "release-archive" and .[0].policy == "exact"
          and .[0].expected == "1.10.18" and .[0].installed == "1.10.20"
          and .[0].status == "outdated"' >/dev/null
}

@test "strict audit accepts Linux Quarto matching a custom archive pin" {
    managed_version_fixture Linux

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        DF_QUARTO_VERSION=1.10.20 DF_VERSION_FIXTURE_QUARTO=1.10.20 \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'any(.[]; .tool == "quarto"
        and .platform == "linux/aarch64" and .manager == "quarto"
        and .source == "release-archive" and .policy == "exact"
        and .expected == "1.10.20" and .installed == "1.10.20"
        and .status == "current")' >/dev/null
}

@test "strict audit rejects Linux Quarto differing from a custom archive pin" {
    managed_version_fixture Linux

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        DF_QUARTO_VERSION=1.10.20 DF_VERSION_FIXTURE_QUARTO=1.10.18 \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 1 ]
    echo "$output" | jq -e '[.[] | select(.status != "current")]
        | length == 1 and .[0].tool == "quarto"
          and .[0].platform == "linux/aarch64" and .[0].manager == "quarto"
          and .[0].source == "release-archive" and .[0].policy == "exact"
          and .[0].expected == "1.10.20" and .[0].installed == "1.10.18"
          and .[0].status == "outdated"' >/dev/null
}

@test "version schema fixture reports missing Julia without calling a host launcher" {
    local host_bin="$BATS_TEST_TMPDIR/host-bin"
    export DF_HOST_JULIA_MARKER="$BATS_TEST_TMPDIR/host-julia-called"
    mkdir -p "$host_bin"
    cat > "$host_bin/julia" <<'SH'
#!/bin/sh
printf 'unexpected host launcher\n' > "$DF_HOST_JULIA_MARKER"
exit 99
SH
    chmod +x "$host_bin/julia"
    export PATH="$host_bin:$PATH"
    managed_version_fixture
    rm "$stub_bin/julia"
    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fixture_path" \
        bash "$REPO/install/audit-versions.sh"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'any(.[]; .tool == "julia" and .status == "missing" and .installed == "")' >/dev/null
    ! grep -qx julia "$DF_VERSION_FIXTURE_LOG"
    [ ! -e "$DF_HOST_JULIA_MARKER" ]
}

@test "current managed version baselines are wired" {
    grep -q 'DF_NVM_VERSION:-v0.40.7' "$REPO/install/node.sh"
    grep -q 'DF_NPM_MAJOR:-12' "$REPO/install/node.sh"
    grep -q 'DF_GO_MIN_VERSION:-1.27' "$REPO/install/go.sh"
    grep -q 'leanprover/lean4:v4.33.1' "$REPO/install/lean.sh"
    grep -q 'DF_QUARTO_VERSION:-1.10.18' "$REPO/install/quarto.sh"
    grep -q 'record rustup 1.29.1 minimum' "$REPO/install/audit-versions.sh"
    grep -q 'record juliaup 1.22.3 minimum' "$REPO/install/audit-versions.sh"
    grep -q 'record julia 1.12.7' "$REPO/install/audit-versions.sh"
}

@test "install and update hold existing Go tools while upgrade refreshes latest" {
    grep -q 'DF_MODE:-install.*!= "upgrade"' "$REPO/install/go.sh"
    grep -q 'upgrade mode refreshes @latest' "$REPO/install/go.sh"
}

@test "new cross-platform tools have one declared owner" {
    [ "$(grep -l '^zizmor$' "$REPO/packages"/*.txt | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(grep -l '^wasm-tools$' "$REPO/packages"/*.txt | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(grep -lE '^ruff([[:space:]]|$)' "$REPO/packages"/*.txt | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(grep -l 'brew "osv-scanner"' "$REPO/packages/Brewfile" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "container bootstrap skips heavyweight toolchains covered by contract tests" {
    grep -q 'DF_DO_QUARTO=0 DF_DO_JULIA=0 DF_DO_LEAN=0 DF_DO_LATEX=0' \
        "$REPO/tests/entrypoint.sh"
    grep -q 'DF_DO_OVERLAYS="${DF_DO_OVERLAYS:-0}"' "$REPO/tests/entrypoint.sh"
}
