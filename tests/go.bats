#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$(mktemp -d)"
    mkdir -p "$TEST_HOME/bin"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "Go entrypoint name comes from the command package path" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/go.sh"
        _go_bin_for_package github.com/example/project/cmd/tool@latest
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "tool" ]
}

@test "Go entrypoint validation requires an executable in GOBIN" {
    touch "$TEST_HOME/bin/tool"
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/go.sh"
        GOBIN="$HOME/bin"
        _go_missing_bin github.com/example/project/cmd/tool@latest
    ' _ "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "tool" ]

    chmod +x "$TEST_HOME/bin/tool"
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/go.sh"
        GOBIN="$HOME/bin"
        _go_missing_bin github.com/example/project/cmd/tool@latest
    ' _ "$REPO"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Go entrypoint validation rejects an executable that cannot start" {
    cat > "$TEST_HOME/bin/tool" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$TEST_HOME/bin/tool"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 DF_TOOL_SMOKE_TIMEOUT=0.2 \
        LC_ALL=C LANG=C bash -c '
        source "$1/install/go.sh"
        GOBIN="$HOME/bin"
        _go_missing_bin github.com/example/project/cmd/tool@latest
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "tool" ]
}
