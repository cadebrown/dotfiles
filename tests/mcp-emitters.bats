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
        mcp_servers_each --all | jq -s -S .
    '
    [ "$status" -eq 0 ]

    # 18 entries, comments/blanks skipped, including three opt-in profiles.
    [ "$(echo "$output" | jq 'length')" -eq 18 ]
    # auth=asta extraction (the newest auth source — added with the math stack)
    [ "$(echo "$output" | jq -r '.[] | select(.name=="astasrv") | .auth')" = "asta" ]
    # stdio parsing keeps the full command string
    [ "$(echo "$output" | jq -r '.[] | select(.name=="tool") | .cmd')" = "uvx some-tool --flag val" ]
    # auth= extraction
    [ "$(echo "$output" | jq -r '.[] | select(.name=="ghsrv") | .auth')" = "gh" ]
    # --codex-client-id is extracted; --client-id stays in extras
    [ "$(echo "$output" | jq -r '.[] | select(.name=="oauthsrv") | .codex_client_id')" = "codex-oauth-id" ]
    [ "$(echo "$output" | jq -r '.[] | select(.name=="oauthsrv") | .extras')" = "--client-id claude-oauth-id" ]
    # --codex-bearer is extracted with its value; nothing leaks into extras
    [ "$(echo "$output" | jq -r '.[] | select(.name=="bearersrv") | .codex_bearer')" = "FIXTURE_BEARER_TOKEN" ]
    [ "$(echo "$output" | jq -r '.[] | select(.name=="bearersrv") | .extras')" = "" ]
    # raw URL is preserved (no substitution in the parser)
    [ "$(echo "$output" | jq -r '.[] | select(.name=="urlkey") | .url')" = 'https://key.example/{FIXTURE_KEY}/v2/mcp' ]
    # Risk/profile metadata is normalized for remote and stdio entries.
    [ "$(echo "$output" | jq -r '.[] | select(.name=="ghsrv") | .risk')" = "external-write" ]
    [ "$(echo "$output" | jq -r '.[] | select(.name=="tool") | .risk')" = "local-write" ]
    [ "$(echo "$output" | jq -r '.[] | select(.name=="scitesrv") | .profile')" = "research-scite" ]
    [ "$(echo "$output" | jq -r '.[] | select(.name=="plainsrv") | .profile')" = "core" ]
}

@test "mcp profiles are opt-in and independently selectable" {
    source "$REPO_ROOT/install/_lib.sh"
    mcp_fixture_env

    run bash -c '
        source "'"$REPO_ROOT"'/install/_lib.sh"
        source "'"$BATS_TEST_DIRNAME"'/lib-mcp-fixture.sh"
        mcp_fixture_env
        mcp_servers_each | jq -r .name
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"scitesrv"* ]]
    [[ "$output" != *"biomedsrv"* ]]
    [[ "$output" != *"publishsrv"* ]]

    run bash -c '
        source "'"$REPO_ROOT"'/install/_lib.sh"
        source "'"$BATS_TEST_DIRNAME"'/lib-mcp-fixture.sh"
        mcp_fixture_env
        export DF_MCP_PROFILES="research-scite:publish"
        mcp_servers_each | jq -r .name
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"scitesrv"* ]]
    [[ "$output" != *"biomedsrv"* ]]
    [[ "$output" == *"publishsrv"* ]]
}

@test "MCP migration selects existing optional entries without activating other profiles" {
    source "$REPO_ROOT/install/_lib.sh"
    mcp_fixture_env
    printf '%s\n' '{"mcp":{"scitesrv":{},"custom":{}}}' > "$HOME/config.json"

    run mcp_servers_for_config "$HOME/config.json" mcp
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"scitesrv"'* ]]
    [[ "$output" != *'"name":"biomedsrv"'* ]]
    [[ "$output" != *'"name":"custom"'* ]]
}

@test "Claude reconciles activated optional servers and preserves custom entries and environment" {
    source "$REPO_ROOT/install/claude.sh"
    mcp_fixture_env
    cat > "$HOME/.claude.json" <<'EOF'
{"mcpServers":{
  "scitesrv":{"type":"http","url":"https://old.example/mcp"},
  "gcsrv":{"type":"http","url":"https://gc.example/mcp","headersHelper":"~/.claude/gcloud-mcp-headers.sh","headers":{"Authorization":"Bearer obsolete-secret"}},
  "misskey":{"type":"http","url":"https://key.example/obsolete-secret/v2/mcp"},
  "tool":{"type":"stdio","command":"old","args":[],"env":{"CUSTOM":"retained"}},
  "custom":{"command":"mine","args":["custom-flag"]}
}}
EOF
    claude() {
        case "$1 $2" in
            'mcp remove')
                jq --arg n "$3" 'del(.mcpServers[$n])' "$HOME/.claude.json" > "$HOME/next.json"
                ;;
            'mcp add-json')
                jq --arg n "$5" --argjson d "$6" '.mcpServers[$n]=$d' "$HOME/.claude.json" > "$HOME/next.json"
                ;;
            *) return 1 ;;
        esac
        mv "$HOME/next.json" "$HOME/.claude.json"
    }
    run_logged() { "$@"; }
    _ok=0 _skip=0 _fail=0
    _register_mcps >/dev/null
    [ "$_fail" -eq 0 ]
    jq -e '.mcpServers.scitesrv.url == "https://scite.example/mcp"
        and .mcpServers.gcsrv.type == "stdio"
        and .mcpServers.gcsrv.command == (env.HOME + "/.local/bin/df-google-mcp")
        and .mcpServers.gcsrv.args == ["https://gc.example/mcp"]
        and (.mcpServers.gcsrv | has("headersHelper") or has("headers") or has("url") | not)
        and .mcpServers.tool.command == "uvx"
        and .mcpServers.tool.env.CUSTOM == "retained"
        and .mcpServers.custom == {command:"mine",args:["custom-flag"]}
        and (.mcpServers | has("misskey") | not)
        and (.mcpServers | has("biomedsrv") | not)' "$HOME/.claude.json"
    _ok=0 _skip=0 _fail=0
    _register_mcps >/dev/null
    [ "$_ok" -eq 0 ]
    [ "$_fail" -eq 0 ]
}

@test "OpenCode sync preserves activated optional and custom MCP entries and disabled choices" {
    source "$REPO_ROOT/install/opencode.sh"
    mcp_fixture_env
    mkdir -p "$HOME/.config/opencode"
    cat > "$HOME/.config/opencode/opencode.json" <<'EOF'
{"mcp":{
  "scitesrv":{"type":"remote","url":"https://old.example/mcp","enabled":false,"timeout":9000},
  "gcsrv":{"type":"remote","url":"https://gc.example/mcp","headers":{"Authorization":"Bearer obsolete-secret"},"enabled":false},
  "misskey":{"type":"remote","url":"https://key.example/obsolete-secret/v2/mcp","enabled":true},
  "custom":{"type":"local","command":["mine"],"enabled":true}
}}
EOF
    chezmoi() { printf '{}\n'; }
    _sync_config >/dev/null
    jq -e '.mcp.scitesrv.url == "https://scite.example/mcp"
        and .mcp.gcsrv.type == "local"
        and .mcp.gcsrv.command == [(env.HOME + "/.local/bin/df-google-mcp"),"https://gc.example/mcp"]
        and .mcp.gcsrv.enabled == false
        and (.mcp.gcsrv | has("headers") or has("url") | not)
        and .mcp.scitesrv.enabled == false
        and .mcp.scitesrv.timeout == 9000
        and .mcp.custom == {type:"local",command:["mine"],enabled:true}
        and .mcp.misskey.url == "https://key.example/{env:FIXTURE_MISSING}/v2/mcp"
        and (.mcp | has("biomedsrv") | not)' "$HOME/.config/opencode/opencode.json"
}

@test "Claude reports a failure when it cannot remove an unavailable URL credential" {
    source "$REPO_ROOT/install/claude.sh"
    mcp_fixture_env
    DF_PACKAGES="$HOME/packages"
    mkdir -p "$DF_PACKAGES"
    printf '%s\n' 'misskey http https://key.example/{FIXTURE_MISSING}/v2/mcp' > "$DF_PACKAGES/mcp-servers.txt"
    printf '%s\n' '{"mcpServers":{"misskey":{"url":"https://key.example/obsolete-secret/v2/mcp"}}}' > "$HOME/.claude.json"
    claude() { return 1; }
    _ok=0 _skip=0 _fail=0
    _register_mcps >/dev/null
    [ "$_fail" -eq 1 ]
    [ "$_skip" -eq 0 ]
}

@test "Cursor sync preserves optional and custom entries while refreshing managed commands" {
    source "$REPO_ROOT/install/cursor.sh"
    mcp_fixture_env
    mkdir -p "$HOME/.cursor"
    cat > "$HOME/.cursor/mcp.json" <<'EOF'
{"userSetting":"retained","mcpServers":{
  "scitesrv":{"url":"https://old.example/mcp","disabled":true,"headers":{"Stale":"remove"}},
  "misskey":{"url":"https://key.example/obsolete-secret/v2/mcp"},
  "gcsrv":{"url":"https://gc.example/mcp","headers":{"Authorization":"Bearer obsolete-secret"}},
  "tool":{"command":"old","args":[],"env":{"CUSTOM":"retained"}},
  "custom":{"command":"mine","args":["custom-flag"]}
}}
EOF
    _sync_cursor_mcp >/dev/null
    jq -e '.userSetting == "retained"
        and .mcpServers.scitesrv.url == "https://scite.example/mcp"
        and .mcpServers.scitesrv.disabled == true
        and (.mcpServers.scitesrv | has("headers") | not)
        and .mcpServers.tool.args == ["-lc","uvx some-tool --flag val"]
        and .mcpServers.tool.env.CUSTOM == "retained"
        and .mcpServers.custom == {command:"mine",args:["custom-flag"]}
        and (.mcpServers | has("misskey") | not)
        and .mcpServers.gcsrv.command == (env.HOME + "/.local/bin/df-google-mcp")
        and .mcpServers.gcsrv.args == ["https://gc.example/mcp"]
        and (.mcpServers.gcsrv | has("headers") | not)
        and (.mcpServers | has("biomedsrv") | not)' "$HOME/.cursor/mcp.json"
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
    _emit_opencode_mcp 2>/dev/null | jq -S . | mcp_fixture_normalize > "$BATS_TEST_TMPDIR/opencode.json"
    diff -u "$BATS_TEST_DIRNAME/golden/opencode-mcp.json" "$BATS_TEST_TMPDIR/opencode.json"
}

@test "cursor emitter matches golden" {
    source "$REPO_ROOT/install/cursor.sh"
    mcp_fixture_env
    _sync_cursor_mcp >/dev/null 2>&1
    jq -S . "$HOME/.cursor/mcp.json" | mcp_fixture_normalize > "$BATS_TEST_TMPDIR/cursor.json"
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

@test "cursor stdio entries resolve through a login shell from a minimal Dock PATH" {
    source "$REPO_ROOT/install/cursor.sh"
    mcp_fixture_env
    fake_bin="$BATS_TEST_TMPDIR/cursor-login-bin"
    result_file="$BATS_TEST_TMPDIR/cursor-login-result"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$CURSOR_TEST_RESULT"\n' \
        > "$fake_bin/solobinary"
    chmod +x "$fake_bin/solobinary"
    printf 'export PATH="%s:$PATH"\n' "$fake_bin" > "$HOME/.bash_profile"
    _sync_cursor_mcp >/dev/null 2>&1

    command="$(jq -r '.mcpServers.bare.command' "$HOME/.cursor/mcp.json")"
    arg0="$(jq -r '.mcpServers.bare.args[0]' "$HOME/.cursor/mcp.json")"
    arg1="$(jq -r '.mcpServers.bare.args[1]' "$HOME/.cursor/mcp.json")"
    run env PATH="/usr/bin:/bin" HOME="$HOME" CURSOR_TEST_RESULT="$result_file" \
        "$command" "$arg0" "$arg1"

    [ "$status" -eq 0 ]
    [ -f "$result_file" ]
}

@test "codex emitter matches golden" {
    source "$REPO_ROOT/install/codex.sh"
    mcp_fixture_env
    _emit_mcp_blocks_to "$BATS_TEST_TMPDIR/codex.toml" >/dev/null 2>&1
    mcp_fixture_normalize < "$BATS_TEST_TMPDIR/codex.toml" > "$BATS_TEST_TMPDIR/codex-normalized.toml"
    diff -u "$BATS_TEST_DIRNAME/golden/codex-mcp.toml" "$BATS_TEST_TMPDIR/codex-normalized.toml"
}

@test "codex approval mode follows MCP risk" {
    source "$REPO_ROOT/install/codex.sh"
    mcp_fixture_env
    _emit_mcp_blocks_to "$BATS_TEST_TMPDIR/codex-risk.toml" >/dev/null 2>&1

    run awk '
        /^\[mcp_servers\.ghsrv\]$/ { found=1; next }
        /^\[/ && found { exit }
        found && /^default_tools_approval_mode/ { print; exit }
    ' "$BATS_TEST_TMPDIR/codex-risk.toml"
    [ "$status" -eq 0 ]
    [ "$output" = 'default_tools_approval_mode = "writes"' ]

    run awk '
        /^\[mcp_servers\.plainsrv\]$/ { found=1; next }
        /^\[/ && found { exit }
        found && /^default_tools_approval_mode/ { print; exit }
    ' "$BATS_TEST_TMPDIR/codex-risk.toml"
    [ "$status" -eq 0 ]
    [ "$output" = 'default_tools_approval_mode = "approve"' ]
}
