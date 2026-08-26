#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_REPO="$BATS_TEST_TMPDIR/repo"
    FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_HOME/.config/cursor" \
        "$TEST_REPO/home/dot_config/cursor" "$FAKE_BIN"

    chezmoi execute-template \
        < "$REPO_ROOT/home/dot_cursor/hooks/executable_sync-dotfiles-cursor.sh.tmpl" \
        > "$BATS_TEST_TMPDIR/cursor-hook.sh"

    cat > "$FAKE_BIN/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "add" ]]
if [[ "${FAKE_CHEZMOI_TRUNCATE:-0}" == 1 ]]; then
    : > "$DF_ROOT/home/dot_config/cursor/${2##*/}"
else
    cp "$2" "$DF_ROOT/home/dot_config/cursor/${2##*/}"
fi
EOF
    chmod +x "$FAKE_BIN/chezmoi"
}

@test "Cursor hook restores the source if settings change during import" {
    printf '%s\n' '{"preserved":true}' \
        > "$TEST_REPO/home/dot_config/cursor/settings.json"
    printf '%s\n' '{"editor.fontSize":15}' \
        > "$TEST_HOME/.config/cursor/settings.json"

    FAKE_CHEZMOI_TRUNCATE=1 run_hook

    [ "$status" -eq 0 ]
    jq -e '.preserved == true' \
        "$TEST_REPO/home/dot_config/cursor/settings.json" >/dev/null
}

run_hook() {
    run env HOME="$TEST_HOME" DF_ROOT="$TEST_REPO" \
        DF_CURSOR_HOOK_SYNC_EXTENSIONS=0 TMPDIR="$BATS_TEST_TMPDIR" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        bash "$BATS_TEST_TMPDIR/cursor-hook.sh"
}

@test "Cursor hook rejects an empty settings file" {
    printf '%s\n' '{"preserved":true}' \
        > "$TEST_REPO/home/dot_config/cursor/settings.json"
    : > "$TEST_HOME/.config/cursor/settings.json"

    run_hook

    [ "$status" -eq 0 ]
    jq -e '.preserved == true' \
        "$TEST_REPO/home/dot_config/cursor/settings.json" >/dev/null
}

@test "Cursor hook imports valid settings and strips remote platform state" {
    printf '%s\n' '{"old":true}' \
        > "$TEST_REPO/home/dot_config/cursor/settings.json"
    printf '%s\n' \
        '{"editor.fontSize":15,"remote.SSH.remotePlatform":{"host":"linux"}}' \
        > "$TEST_HOME/.config/cursor/settings.json"

    run_hook

    [ "$status" -eq 0 ]
    jq -e '."editor.fontSize" == 15 and has("remote.SSH.remotePlatform") == false' \
        "$TEST_REPO/home/dot_config/cursor/settings.json" >/dev/null
}

@test "Cursor hook accepts JSONC keybindings" {
    printf '%s\n' '[{"key":"cmd+i","command":"old"}]' \
        > "$TEST_REPO/home/dot_config/cursor/keybindings.json"
    cat > "$TEST_HOME/.config/cursor/keybindings.json" <<'EOF'
// Cursor writes this leading comment by default.
[
  { "key": "cmd+i", "command": "composerMode.agent" }
]
EOF

    run_hook

    [ "$status" -eq 0 ]
    grep -q 'composerMode.agent' \
        "$TEST_REPO/home/dot_config/cursor/keybindings.json"
}
