#!/usr/bin/env bats

@test "plugin hook gates preserve relevant behavior and survive upgrades" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/hook-scope-test.py"
    if [ "$status" -ne 0 ]; then printf '%s\n' "$output"; fi
    [ "$status" -eq 0 ]
}
