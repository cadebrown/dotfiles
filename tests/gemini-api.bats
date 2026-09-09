#!/usr/bin/env bats

@test "Gemini API probe has locked offline behavior coverage" {
    runtime="$BATS_TEST_DIRNAME/../install/gemini-api.py"
    uv export --quiet --locked --script "$runtime" --format requirements-txt > "$BATS_TEST_TMPDIR/requirements.txt"
    run uv --quiet run --no-project --with-requirements "$BATS_TEST_TMPDIR/requirements.txt" python "$BATS_TEST_DIRNAME/gemini-api-test.py"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}
