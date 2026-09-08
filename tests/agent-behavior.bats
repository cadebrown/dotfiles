#!/usr/bin/env bats

@test "paired instruction checks preserve isolation and native resume evidence" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/agent_behavior_test.py"
    [ "$status" -eq 0 ]
}
