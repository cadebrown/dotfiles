#!/usr/bin/env bats

@test "shared chezmoi guard protects edits with one fresh ownership query" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/chezmoi-guard-test.py"
    if [ "$status" -ne 0 ]; then printf '%s\n' "$output"; fi
    [ "$status" -eq 0 ]
}
