#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_REPO="$BATS_TEST_TMPDIR/repo"
    FAKE_BIN="$BATS_TEST_TMPDIR/bin"

    mkdir -p "$TEST_HOME" "$TEST_REPO/install" "$TEST_REPO/packages" "$FAKE_BIN"
    cp "$REPO_ROOT/install/_lib.sh" "$REPO_ROOT/install/cursor.sh" "$TEST_REPO/install/"

    cat > "$TEST_REPO/packages/cursor-extensions.txt" <<'EOF'
# Cursor extensions
# sync-ignore analytic-signal.preview-mp4
# sync-ignore ms-vscode-remote.remote-ssh-edit
# sync-ignore ms-vscode.cpptools
# sync-ignore ms-vscode.cpptools-extension-pack
# sync-ignore platformio.platformio-ide
tracked.extension
EOF

    cat > "$FAKE_BIN/cursor" <<'EOF'
#!/bin/sh
printf '%s\n' \
    tracked.extension \
    newly.available \
    analytic-signal.preview-mp4 \
    ms-vscode-remote.remote-ssh-edit \
    ms-vscode.cpptools \
    ms-vscode.cpptools-extension-pack \
    platformio.platformio-ide
EOF
    chmod +x "$FAKE_BIN/cursor"
}

@test "Cursor extension sync excludes local-only extensions" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 PATH="$FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_REPO/install/cursor.sh" sync-extensions

    [ "$status" -eq 0 ]
    grep -qx 'newly.available' "$TEST_REPO/packages/cursor-extensions.txt"
    for extension in \
        analytic-signal.preview-mp4 \
        ms-vscode-remote.remote-ssh-edit \
        ms-vscode.cpptools \
        ms-vscode.cpptools-extension-pack \
        platformio.platformio-ide; do
        run grep -qx "$extension" "$TEST_REPO/packages/cursor-extensions.txt"
        [ "$status" -eq 1 ]
        grep -q "^# sync-ignore $extension" \
            "$TEST_REPO/packages/cursor-extensions.txt"
    done
}
