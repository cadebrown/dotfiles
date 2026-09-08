#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export CREDENTIAL_FIXTURE="$BATS_TEST_TMPDIR/credentials"
    mkdir -p "$CREDENTIAL_FIXTURE/bin"
    cat > "$CREDENTIAL_FIXTURE/bin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$CREDENTIAL_FIXTURE/calls"
printf 'fixture-github\n'
EOF
    cat > "$CREDENTIAL_FIXTURE/bin/gcloud" <<'EOF'
#!/bin/sh
printf 'gcloud %s\n' "$*" >> "$CREDENTIAL_FIXTURE/calls"
case "$*" in
    'auth application-default print-access-token') printf 'fixture-google\n' ;;
    'config get-value project') printf 'fixture-project\n' ;;
    *) exit 1 ;;
esac
EOF
    cat > "$CREDENTIAL_FIXTURE/bin/client" <<'EOF'
#!/bin/sh
printf '%s\n' "$GH_TOKEN" "$GOOGLE_MCP_TOKEN" "$GOOGLE_CLOUD_PROJECT" > "$CREDENTIAL_FIXTURE/received"
printf '%s\n' "$*" > "$CREDENTIAL_FIXTURE/arguments"
printf '%s\n' "$@" > "$CREDENTIAL_FIXTURE/argv"
printf 'client-ran\n'
EOF
    chmod +x "$CREDENTIAL_FIXTURE/bin/"*
}

@test "OpenCode launcher resolves GitHub and leaves Google refresh to its transport" {
    local shell_name
    for shell_name in bash zsh; do
        rm -f "$CREDENTIAL_FIXTURE/calls"
        run env -u GH_TOKEN -u GOOGLE_MCP_TOKEN -u GOOGLE_CLOUD_PROJECT \
            PATH="$CREDENTIAL_FIXTURE/bin:$PATH" "$shell_name" -f -c '
                source "$1/home/.chezmoitemplates/opencode-credentials.sh"
                _with_opencode_mcp_credentials command client --auto "prompt with spaces"
            ' _ "$REPO"
        [ "$status" -eq 0 ]
        [ "$output" = client-ran ]
        [ "$(cat "$CREDENTIAL_FIXTURE/calls")" = 'gh auth token' ]
        [ "$(cat "$CREDENTIAL_FIXTURE/received")" = fixture-github ]
        [ "$(cat "$CREDENTIAL_FIXTURE/arguments")" = '--auto prompt with spaces' ]
    done
}

@test "OpenCode shared launcher preserves supplied values without credential calls or output" {
    run env GH_TOKEN=provided-gh GOOGLE_MCP_TOKEN=provided-google GOOGLE_CLOUD_PROJECT=provided-project \
        PATH="$CREDENTIAL_FIXTURE/bin:$PATH" bash -c '
            source "$1/home/.chezmoitemplates/opencode-credentials.sh"
            _with_opencode_mcp_credentials exec client
        ' _ "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = client-ran ]
    [ ! -e "$CREDENTIAL_FIXTURE/calls" ]
    [ "$(cat "$CREDENTIAL_FIXTURE/received")" = $'provided-gh\nprovided-google\nprovided-project' ]
}

@test "local-agent wrapper preserves credentials and leaves native argv ordering to Python" {
    local fixture_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$fixture_home/.local/python/bin"
    cp "$CREDENTIAL_FIXTURE/bin/client" "$fixture_home/.local/python/bin/python"
    run env HOME="$fixture_home" DF_DOTFILES_REPO="$REPO" DF_USE_PLAT=0 \
        GH_TOKEN=provided-gh GOOGLE_MCP_TOKEN=provided-google GOOGLE_CLOUD_PROJECT=provided-project \
        PATH="$CREDENTIAL_FIXTURE/bin:$PATH" bash "$REPO/home/dot_local/bin/executable_local-agent" opencode run "prompt with spaces"
    [ "$status" -eq 0 ]
    [ "$output" = client-ran ]
    [ "$(cat "$CREDENTIAL_FIXTURE/arguments")" = "$REPO/install/local-agent.py opencode run prompt with spaces" ]
    [ "$(cat "$CREDENTIAL_FIXTURE/received")" = $'provided-gh\nprovided-google\nprovided-project' ]
}

@test "OpenCode shell wrappers keep subcommands and delimiter before literal prompt flags" {
    local shell_name
    cp "$CREDENTIAL_FIXTURE/bin/client" "$CREDENTIAL_FIXTURE/bin/opencode"
    mkdir -p "$CREDENTIAL_FIXTURE/models"
    for shell_name in bash zsh; do
        run env GH_TOKEN=provided-gh GOOGLE_MCP_TOKEN=provided-google GOOGLE_CLOUD_PROJECT=provided-project \
            PATH="$CREDENTIAL_FIXTURE/bin:$PATH" "$shell_name" -f -c '
                source "$1/home/.chezmoitemplates/opencode-credentials.sh"
                _opencode_with_defaults run --agent build -- "--auto prompt"
            ' _ "$REPO"
        [ "$status" -eq 0 ]
        [ "$(cat "$CREDENTIAL_FIXTURE/argv")" = $'run\n--agent\nbuild\n--auto\n--\n--auto prompt' ]
        run env GH_TOKEN=provided-gh GOOGLE_MCP_TOKEN=provided-google GOOGLE_CLOUD_PROJECT=provided-project \
            PATH="$CREDENTIAL_FIXTURE/bin:$PATH" "$shell_name" -f -c '
                source "$1/home/.chezmoitemplates/opencode-credentials.sh"
                cd "$CREDENTIAL_FIXTURE"
                _opencode_with_defaults models --help
            ' _ "$REPO"
        [ "$status" -eq 0 ]
        [ "$(cat "$CREDENTIAL_FIXTURE/argv")" = $'models\n--help' ]
        run env GH_TOKEN=provided-gh GOOGLE_MCP_TOKEN=provided-google GOOGLE_CLOUD_PROJECT=provided-project \
            PATH="$CREDENTIAL_FIXTURE/bin:$PATH" "$shell_name" -f -c '
                source "$1/home/.chezmoitemplates/opencode-credentials.sh"
                _opencode_with_defaults run --no-auto prompt
            ' _ "$REPO"
        [ "$status" -eq 0 ]
        [ "$(cat "$CREDENTIAL_FIXTURE/argv")" = $'run\n--no-auto\nprompt' ]
    done
}
