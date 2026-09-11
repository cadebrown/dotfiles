#!/usr/bin/env bats

setup() {
    local chezmoi_bin
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_BIN"
    cat > "$TEST_BIN/claude" <<'EOF'
#!/bin/sh
printf '<call>\n'
printf '<%s>\n' "$@"
EOF
    chmod +x "$TEST_BIN/claude"
    chezmoi_bin="${CHEZMOI_BIN:-$(command -v chezmoi)}"
    "$chezmoi_bin" execute-template < "$REPO_ROOT/home/.chezmoitemplates/claude-defaults.sh" \
        > "$BATS_TEST_TMPDIR/claude-defaults.sh"
}

run_wrapper() {
    local shell="$1"
    shift
    run env PATH="$TEST_BIN:$PATH" "$shell" -c \
        '. "$1"; shift; claude() { _claude_with_defaults "$@"; }; claude "$@"' \
        _ "$BATS_TEST_TMPDIR/claude-defaults.sh" "$@"
}

assert_session_defaults() {
    [[ "$output" == $'<call>\n<--model>\n<claude-opus-5[1m]>\n<--effort>\n<medium>'* ]]
}

@test "Claude launcher adds Opus 5 1M and medium in Bash and Zsh" {
    local shell
    for shell in bash zsh; do
        run_wrapper "$shell" -p 'hello'
        [ "$status" -eq 0 ]
        assert_session_defaults
        [[ "$output" == *$'<-p>\n<hello>' ]]
        [ "$(grep -c '^<call>$' <<< "$output")" -eq 1 ]
    done
}

@test "Claude launcher preserves explicit model and effort flags" {
    local shell
    for shell in bash zsh; do
        run_wrapper "$shell" --model sonnet --effort=high -p hello
        [ "$status" -eq 0 ]
        [ "$output" = $'<call>\n<--model>\n<sonnet>\n<--effort=high>\n<-p>\n<hello>' ]

        run_wrapper "$shell" -m=haiku -p hello
        [ "$status" -eq 0 ]
        [ "$output" = $'<call>\n<--effort>\n<medium>\n<-m=haiku>\n<-p>\n<hello>' ]

        run_wrapper "$shell" --effort low -p hello
        [ "$status" -eq 0 ]
        [ "$output" = $'<call>\n<--model>\n<claude-opus-5[1m]>\n<--effort>\n<low>\n<-p>\n<hello>' ]
    done
}

@test "Claude launcher leaves management commands untouched" {
    local shell command
    for shell in bash zsh; do
        for command in mcp update plugin auth doctor; do
            run_wrapper "$shell" "$command" probe --flag
            [ "$status" -eq 0 ]
            [ "$output" = "<call>"$'\n'"<$command>"$'\n'"<probe>"$'\n'"<--flag>" ]
        done
    done
}
