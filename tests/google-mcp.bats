#!/usr/bin/env bats

@test "Google MCP refreshes ADC in one stdio session and preserves the upstream protocol" {
    runtime="$BATS_TEST_DIRNAME/../install/google-mcp.py"
    uv export --quiet --locked --script "$runtime" --format requirements-txt > "$BATS_TEST_TMPDIR/requirements.txt"
    run uv --quiet run --no-project --with-requirements "$BATS_TEST_TMPDIR/requirements.txt" python "$BATS_TEST_DIRNAME/google-mcp-test.py"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}
