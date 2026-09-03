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
    run bash "$REPO/install/audit-versions.sh"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length >= 16' >/dev/null
    echo "$output" | jq -e 'all(.[];
        has("tool") and has("manager") and has("expected") and
        has("policy") and has("installed") and has("status") and
        has("source") and has("platform"))' >/dev/null
    echo "$output" | jq -e 'all(.[].status; . == "current" or . == "outdated" or . == "missing")' >/dev/null
}

@test "strict audit accepts patch releases newer than minimum floors" {
    local fake_home="$BATS_TEST_TMPDIR/audit-home"
    local stub_bin="$BATS_TEST_TMPDIR/audit-bin"
    local command
    mkdir -p "$fake_home/.local/nvm" "$stub_bin"
    printf '%s\n' 'nvm() { printf "0.40.7\\n"; }' \
        > "$fake_home/.local/nvm/nvm.sh"

    cat > "$stub_bin/managed-version" <<'EOF'
#!/usr/bin/env bash
case "${0##*/}" in
    rustup)  printf 'rustup 1.29.2\n' ;;
    rustc)   printf 'rustc 1.98.0 (test)\n' ;;
    node)    printf 'v24.20.0\n' ;;
    npm)     printf '12.0.2\n' ;;
    python3) printf 'Python 3.14.7\n' ;;
    uv)      printf 'uv 0.12.9\n' ;;
    go)      printf 'go version go1.27.1 linux/arm64\n' ;;
    zig)     printf '0.16.0\n' ;;
    juliaup) printf 'Juliaup 1.22.4\n' ;;
    julia)   printf 'julia version 1.12.7\n' ;;
    lean)    printf 'Lean (version 4.33.1, test)\n' ;;
    cmake)   printf 'cmake version 4.4.3\n' ;;
    ninja)   printf '1.13.2\n' ;;
    quarto)  printf '1.10.18\n' ;;
    brew)    printf 'llvm@22 22.1.8\n' ;;
esac
EOF
    chmod 755 "$stub_bin/managed-version"
    for command in rustup rustc node npm python3 uv go zig juliaup julia lean \
        cmake ninja quarto brew; do
        ln -s managed-version "$stub_bin/$command"
    done

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$stub_bin:$PATH" \
        bash "$REPO/install/audit-versions.sh" --strict

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '
        .[] | select(.tool == "rustup" or .tool == "juliaup")
        | .policy == "minimum" and .status == "current"
    ' >/dev/null
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
