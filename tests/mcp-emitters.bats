#!/usr/bin/env bats
# tests/mcp-emitters.bats — golden tests for the four MCP config emitters.
#
# All emitters render packages/mcp-servers.txt (parsed by mcp_servers_each in
# install/_lib.sh) into per-tool config. These tests feed the fixture list
# (tests/fixtures/mcp/mcp-servers.txt) through each emitter and diff against
# tests/golden/*. A failure means the OUTPUT SHAPE changed: if intentional,
# re-run tests/capture-mcp-goldens.sh and commit the golden diff alongside.
#
# Runs locally with brew-installed bats-core, and inside tests/run.sh docker.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _MCP_FIXTURE_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$_MCP_FIXTURE_HOME"
    source "$BATS_TEST_DIRNAME/lib-mcp-fixture.sh"
}

@test "mcp_servers_each parses every fixture entry with normalized fields" {
    source "$REPO_ROOT/install/_lib.sh"
    mcp_fixture_env

    run bash -c '
        source "'"$REPO_ROOT"'/install/_lib.sh"
        source "'"$BATS_TEST_DIRNAME"'/lib-mcp-fixture.sh"
        mcp_fixture_env
        mcp_servers_each | jq -s -S .
    '
    [ "$status" -eq 0 ]

    # 12 entries, comments/blanks skipped
    [ "$(echo "$output" | jq 'length')" -eq 12 ]
    # stdio parsing keeps the full command string
    [ "$(echo "$output" | jq -r '.[] | select(.name=="tool") | .cmd')" = "uvx some-tool --flag val" ]
    # auth= extraction
    [ "$(echo "$output" | jq -r '.[] | select(.name=="ghsrv") | .auth')" = "gh" ]
    # --codex-client-id is extracted; --client-id stays in extras
    [ "$(echo "$output" | jq -r '.[] | select(.name=="oauthsrv") | .codex_client_id')" = "codex-oauth-id" ]
    [ "$(echo "$output" | jq -r '.[] | select(.name=="oauthsrv") | .extras')" = "--client-id claude-oauth-id" ]
    # raw URL is preserved (no substitution in the parser)
    [ "$(echo "$output" | jq -r '.[] | select(.name=="urlkey") | .url')" = 'https://key.example/{FIXTURE_KEY}/v2/mcp' ]
}

@test "mcp_url_substitute expands placeholders and reports missing vars" {
    source "$REPO_ROOT/install/_lib.sh"
    export FIXTURE_KEY="fixture-url-key"
    unset FIXTURE_MISSING 2>/dev/null || true

    run mcp_url_substitute 'https://key.example/{FIXTURE_KEY}/v2/mcp'
    [ "$status" -eq 0 ]
    [ "$output" = "https://key.example/fixture-url-key/v2/mcp" ]

    run mcp_url_substitute 'https://key.example/{FIXTURE_MISSING}/v2/mcp'
    [ "$status" -eq 1 ]
    [ "$output" = "FIXTURE_MISSING" ]
}

@test "opencode emitter matches golden" {
    source "$REPO_ROOT/install/opencode.sh"
    mcp_fixture_env
    _emit_opencode_mcp 2>/dev/null | jq -S . > "$BATS_TEST_TMPDIR/opencode.json"
    diff -u "$BATS_TEST_DIRNAME/golden/opencode-mcp.json" "$BATS_TEST_TMPDIR/opencode.json"
}

@test "cursor emitter matches golden" {
    source "$REPO_ROOT/install/cursor.sh"
    mcp_fixture_env
    _sync_cursor_mcp >/dev/null 2>&1
    jq -S . "$HOME/.cursor/mcp.json" > "$BATS_TEST_TMPDIR/cursor.json"
    diff -u "$BATS_TEST_DIRNAME/golden/cursor-mcp.json" "$BATS_TEST_TMPDIR/cursor.json"
}

@test "cursor emitter is idempotent (second run reports unchanged)" {
    source "$REPO_ROOT/install/cursor.sh"
    mcp_fixture_env
    _sync_cursor_mcp >/dev/null 2>&1
    run _sync_cursor_mcp
    [ "$status" -eq 0 ]
    [[ "$output" == *"unchanged"* ]]
}

@test "codex emitter matches golden" {
    source "$REPO_ROOT/install/codex.sh"
    mcp_fixture_env
    _emit_mcp_blocks_to "$BATS_TEST_TMPDIR/codex.toml" >/dev/null 2>&1
    diff -u "$BATS_TEST_DIRNAME/golden/codex-mcp.toml" "$BATS_TEST_TMPDIR/codex.toml"
}
