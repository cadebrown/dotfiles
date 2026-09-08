#!/usr/bin/env bats

@test "statusline incrementally accounts for transcripts and recovers cache invalidation" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/statusline_test.py"
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output" >&2
        return "$status"
    fi
}
