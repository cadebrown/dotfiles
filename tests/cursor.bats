#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_REPO="$BATS_TEST_TMPDIR/repo with spaces"
    FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_HOME/.config/cursor" \
        "$TEST_REPO/home/dot_config/cursor" "$FAKE_BIN"

    chezmoi execute-template \
        < "$REPO_ROOT/home/dot_cursor/hooks/executable_sync-dotfiles-cursor.sh.tmpl" \
        > "$BATS_TEST_TMPDIR/cursor-hook.sh"

    cp "$REPO_ROOT/home/dot_cursor/hooks/sync_dotfiles_cursor.py" "$BATS_TEST_TMPDIR/"
    ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$FAKE_BIN/python3"

    cat > "$FAKE_BIN/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "add" ]]
printf '%s\n' "$2" >> "$DF_ROOT/imports.log"
[[ "${FAKE_CHEZMOI_FAIL:-0}" != 1 ]] || exit 1
if [[ "${FAKE_CHEZMOI_DELAY:-0}" != 0 ]]; then sleep "$FAKE_CHEZMOI_DELAY"; fi
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
        DF_CURSOR_HOOK_SYNC_EXTENSIONS="${DF_CURSOR_HOOK_SYNC_EXTENSIONS:-0}" TMPDIR="$BATS_TEST_TMPDIR" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        bash "$BATS_TEST_TMPDIR/cursor-hook.sh" "$@"
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

@test "Cursor unchanged prompts do no import or extension inventory" {
    printf '%s\n' '{"editor.fontSize":15}' > "$TEST_HOME/.config/cursor/settings.json"
    mkdir -p "$TEST_REPO/install"
    printf '%s\n' '#!/bin/sh' 'touch "$DF_ROOT/extensions-ran"' > "$TEST_REPO/install/cursor.sh"
    DF_CURSOR_HOOK_SYNC_EXTENSIONS=1 run_hook --before-submit
    [ "$status" -eq 0 ]
    run_hook --before-submit
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_REPO/imports.log" | tr -d ' ')" -eq 1 ]
    [ ! -e "$TEST_REPO/extensions-ran" ]
    [[ "$output" == *'{"continue":true}'* ]]
}

@test "Cursor imports changed live or source files immediately without debounce" {
    printf '%s\n' '{"editor.fontSize":15}' > "$TEST_HOME/.config/cursor/settings.json"
    run_hook --before-submit
    printf '%s\n' '{"editor.fontSize":16}' > "$TEST_HOME/.config/cursor/settings.json"
    run_hook --before-submit
    [ "$status" -eq 0 ]
    jq -e '."editor.fontSize" == 16' "$TEST_REPO/home/dot_config/cursor/settings.json"
    printf '%s\n' '{"stale":true}' > "$TEST_REPO/home/dot_config/cursor/settings.json"
    run_hook --before-submit
    [ "$(wc -l < "$TEST_REPO/imports.log" | tr -d ' ')" -eq 3 ]
    jq -e '."editor.fontSize" == 16' "$TEST_REPO/home/dot_config/cursor/settings.json"
}

@test "Cursor retries failed and unstable imports on the next prompt" {
    printf '%s\n' '{"preserved":true}' > "$TEST_REPO/home/dot_config/cursor/settings.json"
    printf '%s\n' '{"editor.fontSize":15}' > "$TEST_HOME/.config/cursor/settings.json"
    FAKE_CHEZMOI_FAIL=1 run_hook --before-submit
    [[ "$output" == *'will retry'* ]]
    jq -e '.preserved == true' "$TEST_REPO/home/dot_config/cursor/settings.json"
    FAKE_CHEZMOI_TRUNCATE=1 run_hook --before-submit
    jq -e '.preserved == true' "$TEST_REPO/home/dot_config/cursor/settings.json"
    run_hook --before-submit
    jq -e '."editor.fontSize" == 15' "$TEST_REPO/home/dot_config/cursor/settings.json"
    [ "$(wc -l < "$TEST_REPO/imports.log" | tr -d ' ')" -eq 3 ]
}

@test "Cursor accepts JSONC settings and strips machine keys without corrupting strings" {
    cat > "$TEST_HOME/.config/cursor/settings.json" <<'EOF'
// user preferences
{
  "url": "https://example.com/},]", /* valid block comment */
  "escaped": "a\"//b",
  "remote.SSH.remotePlatform": {"host":"linux"},
}
EOF
    run_hook
    [ "$status" -eq 0 ]
    jq -e '.url == "https://example.com/},]" and has("remote.SSH.remotePlatform") == false' \
        "$TEST_REPO/home/dot_config/cursor/settings.json"
}

@test "Cursor rejects syntactically malformed settings and retries after repair" {
    printf '%s\n' '{bad}' > "$TEST_HOME/.config/cursor/settings.json"
    run_hook
    [ ! -e "$TEST_REPO/imports.log" ]
    [[ "$output" == *'will retry'* ]]
    printf '%s\n' '{"valid":true}' > "$TEST_HOME/.config/cursor/settings.json"
    run_hook
    jq -e '.valid == true' "$TEST_REPO/home/dot_config/cursor/settings.json"
}

@test "Cursor inventories extensions at session end only and reports failures" {
    mkdir -p "$TEST_REPO/install"
    printf '%s\n' '#!/bin/sh' 'touch "$DF_ROOT/extensions-ran"' 'exit "${FAKE_EXT_RC:-0}"' > "$TEST_REPO/install/cursor.sh"
    run env HOME="$TEST_HOME" DF_ROOT="$TEST_REPO" \
        DF_CURSOR_HOOK_SYNC_EXTENSIONS=1 PATH="$FAKE_BIN:/usr/bin:/bin" \
        bash "$BATS_TEST_TMPDIR/cursor-hook.sh" --session-end
    [ "$status" -eq 0 ]
    [ -e "$TEST_REPO/extensions-ran" ]
    run env HOME="$TEST_HOME" DF_ROOT="$TEST_REPO" FAKE_EXT_RC=1 \
        PATH="$FAKE_BIN:/usr/bin:/bin" bash "$BATS_TEST_TMPDIR/cursor-hook.sh" --session-end
    [[ "$output" == *'extension sync failed'* ]]
}

@test "Cursor serializes simultaneous prompts and keeps fingerprint state private" {
    printf '%s\n' '{"editor.fontSize":15}' > "$TEST_HOME/.config/cursor/settings.json"
    env HOME="$TEST_HOME" DF_ROOT="$TEST_REPO" FAKE_CHEZMOI_DELAY=0.2 \
        PATH="$FAKE_BIN:/usr/bin:/bin" bash "$BATS_TEST_TMPDIR/cursor-hook.sh" --before-submit > "$BATS_TEST_TMPDIR/first.log" &
    first=$!
    run_hook --before-submit
    wait "$first"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_REPO/imports.log" | tr -d ' ')" -eq 1 ]
    run env HOME="$TEST_HOME" "$FAKE_BIN/python3" -c '
from pathlib import Path
import json
import os
cache = next((Path.home() / ".cache/dotfiles/cursor-hook").glob("*/fingerprints.json"))
assert cache.stat().st_mode & 0o777 == 0o600
assert cache.parent.stat().st_mode & 0o777 == 0o700
state = json.loads(cache.read_text())
assert all(len(value) == 64 for value in state["settings.json"].values())
'
    [ "$status" -eq 0 ]
}

@test "Cursor rebuilds a corrupt cache instead of missing subsequent changes" {
    printf '%s\n' '{"valid":true}' > "$TEST_HOME/.config/cursor/settings.json"
    run_hook
    printf '%s\n' 'broken' > "$TEST_HOME"/.cache/dotfiles/cursor-hook/*/fingerprints.json
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *'rebuilding unreadable fingerprint cache'* ]]
    [ "$(wc -l < "$TEST_REPO/imports.log" | tr -d ' ')" -eq 2 ]
}

@test "Cursor warns on a missing helper while preserving the prompt response" {
    rm "$BATS_TEST_TMPDIR/sync_dotfiles_cursor.py"
    run_hook --before-submit
    [ "$status" -eq 0 ]
    [[ "$output" == *'sync helper missing'* ]]
    [[ "$output" == *'{"continue":true}'* ]]
}

@test "Cursor prompt imports proceed while session-end extension inventory is running" {
    mkdir -p "$TEST_REPO/install"
    cat > "$TEST_REPO/install/cursor.sh" <<'EOF'
#!/bin/sh
touch "$DF_ROOT/extension-started"
while [ ! -f "$DF_ROOT/extension-release" ]; do sleep 0.05; done
EOF
    run env HOME="$TEST_HOME" DF_ROOT="$TEST_REPO" \
        HOOK_SCRIPT="$BATS_TEST_TMPDIR/cursor-hook.sh" \
        PATH="$FAKE_BIN:/usr/bin:/bin" "$FAKE_BIN/python3" - <<'PY'
import os
from pathlib import Path
import subprocess
import time
root = Path(os.environ['DF_ROOT'])
command = ['bash', os.environ['HOOK_SCRIPT']]
background = subprocess.Popen(command + ['--session-end'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    deadline = time.monotonic() + 3
    while not (root / 'extension-started').exists():
        assert time.monotonic() < deadline, 'extension inventory failed to start'
        time.sleep(0.01)
    (Path.home() / '.config/cursor/settings.json').write_text('{"changed":true}')
    result = subprocess.run(command + ['--before-submit'], capture_output=True, timeout=1, check=True)
    assert (root / 'home/dot_config/cursor/settings.json').read_text() == '{"changed":true}'
    assert b'continue' in result.stdout
    assert background.poll() is None
finally:
    (root / 'extension-release').touch()
    background.communicate(timeout=5)
PY
    [ "$status" -eq 0 ]
}
