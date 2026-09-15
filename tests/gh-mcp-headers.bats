#!/usr/bin/env bats

setup() {
    export REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HELPER="$REPO/home/dot_claude/executable_gh-mcp-headers.sh"
    export TEST_HOME="$BATS_TEST_TMPDIR/home"
    export FIXTURE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_HOME" "$FIXTURE_BIN"
    cat > "$FIXTURE_BIN/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_CALLS"
printf '%s' "${GH_FIXTURE_TOKEN:-fallback-token}"
EOF
    chmod +x "$FIXTURE_BIN/gh"
}

run_helper() {
    run env -u GH_TOKEN -u GITHUB_TOKEN HOME="$TEST_HOME" GH_CALLS="$BATS_TEST_TMPDIR/gh-calls" \
        PATH="$FIXTURE_BIN:$PATH" "$@" bash "$HELPER"
}

@test "GitHub MCP headers use the runtime resolver in a minimal app-server PATH" {
    local runtime_repo="$BATS_TEST_TMPDIR/runtime-repo"
    local runtime_bin="$BATS_TEST_TMPDIR/runtime-bin"
    mkdir -p "$runtime_repo/install" "$runtime_bin"
    ln -s "$(command -v jq)" "$runtime_bin/jq"
    cat > "$runtime_repo/install/agent-runtime.sh" <<'EOF'
[[ "${1:-}" == --runtime-only ]] || return 1
ARCH_BIN="$GH_RUNTIME_BIN"
LOCAL_PLAT="$GH_RUNTIME_LOCAL"
export ARCH_BIN LOCAL_PLAT
EOF

    run env -u GITHUB_TOKEN HOME="$TEST_HOME" GH_TOKEN=minimal-path-token \
        GH_CALLS="$BATS_TEST_TMPDIR/gh-calls" GH_RUNTIME_BIN="$runtime_bin" \
        GH_RUNTIME_LOCAL="$BATS_TEST_TMPDIR/unused-local" DF_DOTFILES_REPO="$runtime_repo" \
        PATH="$FIXTURE_BIN" /bin/bash "$HELPER"
    [ "$status" -eq 0 ]
    [ "$output" = '{"Authorization":"Bearer minimal-path-token"}' ]
}

@test "GitHub MCP headers report a failed runtime resolver" {
    local runtime_repo="$BATS_TEST_TMPDIR/broken-runtime-repo"
    mkdir -p "$runtime_repo/install"
    printf '%s\n' 'return 1' > "$runtime_repo/install/agent-runtime.sh"

    run env -u GH_TOKEN -u GITHUB_TOKEN HOME="$TEST_HOME" DF_DOTFILES_REPO="$runtime_repo" \
        PATH="$FIXTURE_BIN" /bin/bash "$HELPER"
    [ "$status" -ne 0 ]
    [[ "$output" == *'could not resolve app-server paths'* ]]
}

@test "GitHub MCP headers prefer GH_TOKEN over GITHUB_TOKEN and the managed file" {
    printf '%s\n' 'GITHUB_TOKEN=file-token' > "$TEST_HOME/.github.env"

    run_helper GH_TOKEN=explicit-gh GITHUB_TOKEN=explicit-github
    [ "$status" -eq 0 ]
    [ "$output" = '{"Authorization":"Bearer explicit-gh"}' ]
    [ ! -e "$BATS_TEST_TMPDIR/gh-calls" ]
}

@test "GitHub MCP headers use GITHUB_TOKEN before the managed file" {
    printf '%s\n' 'GITHUB_TOKEN=file-token' > "$TEST_HOME/.github.env"

    run_helper GITHUB_TOKEN=explicit-github
    [ "$status" -eq 0 ]
    [ "$output" = '{"Authorization":"Bearer explicit-github"}' ]
    [ ! -e "$BATS_TEST_TMPDIR/gh-calls" ]
}

@test "GitHub MCP headers load only the managed GitHub env file" {
    printf '%s\n' 'GITHUB_TOKEN=file-token' > "$TEST_HOME/.github.env"
    printf '%s\n' 'GITHUB_TOKEN=unrelated-service-token' > "$TEST_HOME/.nvidia.env"

    run_helper
    [ "$status" -eq 0 ]
    [ "$output" = '{"Authorization":"Bearer file-token"}' ]
    [ ! -e "$BATS_TEST_TMPDIR/gh-calls" ]
}

@test "GitHub MCP headers fall back to gh auth token" {
    run_helper GH_FIXTURE_TOKEN=gh-fallback
    [ "$status" -eq 0 ]
    [ "$output" = '{"Authorization":"Bearer gh-fallback"}' ]
    [ "$(cat "$BATS_TEST_TMPDIR/gh-calls")" = 'auth token' ]
}

@test "GitHub MCP headers fail actionably when no credential source succeeds" {
    cat > "$FIXTURE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$FIXTURE_BIN/gh"

    run_helper
    [ "$status" -ne 0 ]
    [[ "$output" == *'no credential found'* ]]
    [[ "$output" != *'{}'* ]]
}

@test "GitHub MCP headers report a managed GitHub env load failure" {
    printf '%s\n' 'return 1' > "$TEST_HOME/.github.env"

    run_helper
    [ "$status" -ne 0 ]
    [[ "$output" == *'could not load'*'.github.env'* ]]
}

@test "GitHub MCP headers JSON-escape unusual credential characters" {
    printf 'GITHUB_TOKEN=%q\n' $'quote" slash\\' > "$TEST_HOME/.github.env"

    run_helper
    [ "$status" -eq 0 ]
    run jq -r '.Authorization' <<< "$output"
    [ "$status" -eq 0 ]
    [ "$output" = $'Bearer quote" slash\\' ]
}

@test "Codex healthcheck requires the GitHub helper in its MCP section" {
    local config="$BATS_TEST_TMPDIR/config.toml"
    mkdir -p "$TEST_HOME/.claude"
    cp "$HELPER" "$TEST_HOME/.claude/gh-mcp-headers.sh"
    chmod +x "$TEST_HOME/.claude/gh-mcp-headers.sh"

    run env HOME="$TEST_HOME" REPO="$REPO" CONFIG="$config" bash -c '
        source "$REPO/install/codex.sh"
        _emit_mcp_blocks_to "$CONFIG" >/dev/null
        _check_github_mcp_config "$CONFIG"
    '
    [ "$status" -eq 0 ]
}

@test "Codex healthcheck rejects legacy GitHub bearer config and a missing helper" {
    local config="$BATS_TEST_TMPDIR/config.toml"
    cat > "$config" <<'EOF'
[mcp_servers.github]
bearer_token_env_var = "GH_TOKEN"
EOF

    run env HOME="$TEST_HOME" REPO="$REPO" CONFIG="$config" bash -c '
        source "$REPO/install/codex.sh"
        _check_github_mcp_config "$CONFIG"
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *'missing http_headers_helper'* ]]

    cat > "$config" <<EOF
[mcp_servers.github]
http_headers_helper = "bash \"$TEST_HOME/.claude/gh-mcp-headers.sh\""
EOF
    run env HOME="$TEST_HOME" REPO="$REPO" CONFIG="$config" bash -c '
        source "$REPO/install/codex.sh"
        _check_github_mcp_config "$CONFIG"
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *'Missing executable GitHub MCP headers helper'* ]]
}
