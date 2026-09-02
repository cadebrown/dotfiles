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

@test "current managed version baselines are wired" {
    grep -q 'DF_NVM_VERSION:-v0.40.7' "$REPO/install/node.sh"
    grep -q 'DF_NPM_MAJOR:-12' "$REPO/install/node.sh"
    grep -q 'DF_GO_MIN_VERSION:-1.27' "$REPO/install/go.sh"
    grep -q 'leanprover/lean4:v4.33.1' "$REPO/install/lean.sh"
    grep -q 'DF_QUARTO_VERSION:-1.10.18' "$REPO/install/quarto.sh"
    grep -q 'record juliaup 1.22.2' "$REPO/install/audit-versions.sh"
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
