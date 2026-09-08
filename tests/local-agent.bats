#!/usr/bin/env bats

@test "local-agent verifies model readiness and owns only the server it starts" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/local-agent-test.py"
    [ "$status" -eq 0 ]
}
