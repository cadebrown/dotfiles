#!/usr/bin/env bats

@test "browser workspaces isolate profiles and preserve attachment ownership" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/browser-sessions-test.py"
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output" >&2
    fi
    [ "$status" -eq 0 ]
}
