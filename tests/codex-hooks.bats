#!/usr/bin/env bats

@test "native Codex trusts every installed lifecycle hook" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/codex-hooks-test.py"
    if [ "$status" -ne 0 ]; then printf '%s\n' "$output"; fi
    [ "$status" -eq 0 ]
}
