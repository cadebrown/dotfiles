#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    FAKE_REPO="$BATS_TEST_TMPDIR/repo"
    CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$TEST_HOME/.local/bin" "$FAKE_REPO"
    ln -s "$REPO/install" "$FAKE_REPO/install"
    export HOME="$TEST_HOME" CALLS

    cat > "$TEST_HOME/.local/bin/uvx" <<'EOF'
#!/usr/bin/env bash
printf 'id=%s|secret=%s|path=%s|loopback=%s\n' "${GOOGLE_OAUTH_CLIENT_ID:-}" "${GOOGLE_OAUTH_CLIENT_SECRET:-}" "${GOOGLE_CLIENT_SECRET_PATH:-}" "${OAUTHLIB_INSECURE_TRANSPORT:-}" >> "$CALLS"
printf 'arg=%s\n' "$@" >> "$CALLS"
printf 'workspace MCP launched\n'
EOF
    chmod +x "$TEST_HOME/.local/bin/uvx"
}

@test "workspace MCP launcher loads client credentials for uvx without printing them" {
    cat > "$HOME/.google.env" <<'EOF'
export GOOGLE_OAUTH_CLIENT_ID=client\ id
export GOOGLE_OAUTH_CLIENT_SECRET=client\ secret
EOF

    run env -i HOME="$HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" CALLS="$CALLS" \
        bash "$REPO/home/dot_local/bin/executable_df-workspace-mcp" \
        --tools gmail drive docs slides sheets --tool-tier complete

    [ "$status" -eq 0 ]
    [ "$output" = "workspace MCP launched" ]
    [[ "$output" != *"client id"* ]]
    [[ "$output" != *"client secret"* ]]
    grep -Fx 'id=client id|secret=client secret|path=|loopback=1' "$CALLS"
    grep -Fx 'arg=workspace-mcp==1.26.2' "$CALLS"
    grep -Fx 'arg=--tools' "$CALLS"
    grep -Fx 'arg=complete' "$CALLS"
}

@test "workspace MCP launcher preserves explicitly supplied client credentials" {
    cat > "$HOME/.google.env" <<'EOF'
export GOOGLE_OAUTH_CLIENT_ID=file-client
export GOOGLE_OAUTH_CLIENT_SECRET=file-secret
EOF

    run env -i HOME="$HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" CALLS="$CALLS" \
        GOOGLE_OAUTH_CLIENT_ID=environment-client GOOGLE_OAUTH_CLIENT_SECRET=environment-secret \
        bash "$REPO/home/dot_local/bin/executable_df-workspace-mcp" --tools docs

    [ "$status" -eq 0 ]
    grep -Fx 'id=environment-client|secret=environment-secret|path=|loopback=1' "$CALLS"
}

@test "workspace MCP launcher preserves an explicitly supplied client-secret path" {
    cat > "$HOME/.google.env" <<'EOF'
export GOOGLE_OAUTH_CLIENT_ID=file-client
export GOOGLE_OAUTH_CLIENT_SECRET=file-secret
EOF

    run env -i HOME="$HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" CALLS="$CALLS" \
        GOOGLE_CLIENT_SECRET_PATH=/private/client.json \
        bash "$REPO/home/dot_local/bin/executable_df-workspace-mcp" --tools slides

    [ "$status" -eq 0 ]
    grep -Fx 'id=|secret=|path=/private/client.json|loopback=1' "$CALLS"
}
