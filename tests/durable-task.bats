#!/usr/bin/env bats

@test "durable task checkpoints preserve native cancellation and job ownership" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/durable-task-test.py"
    if [ "$status" -ne 0 ]; then printf '%s\n' "$output"; fi
    [ "$status" -eq 0 ]
}
