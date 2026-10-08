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

setup_installer() {
    INSTALL_REPO="$BATS_TEST_TMPDIR/repo"
    INSTALL_HOME="$BATS_TEST_TMPDIR/home"
    INSTALL_TOOLS="$BATS_TEST_TMPDIR/tools"
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude-calls.log"
    mkdir -p "$INSTALL_REPO/install" "$INSTALL_REPO/packages" \
        "$INSTALL_REPO/home/.chezmoitemplates" "$INSTALL_HOME" "$INSTALL_TOOLS/bin"
    cp "$REPO_ROOT/install/claude.sh" "$REPO_ROOT/install/_lib.sh" \
        "$REPO_ROOT/install/_host-config.sh" "$REPO_ROOT/install/_runtime-paths.sh" \
        "$INSTALL_REPO/install/"
    cp "$REPO_ROOT/home/.chezmoitemplates/compiler-cache.sh" \
        "$INSTALL_REPO/home/.chezmoitemplates/"
    printf '%s\n' 'fixture@trailofbits' > "$INSTALL_REPO/packages/claude-plugins.txt"
    cat > "$TEST_BIN/curl" <<'SH'
#!/bin/sh
case "$*" in
    *https://downloads.claude.ai/claude-code-releases/latest) printf '%s\n' 2.1.294 ;;
    *) exit 90 ;;
esac
SH
    cat > "$TEST_BIN/claude" <<'SH'
#!/bin/sh
if [ "$*" = --version ]; then
    printf '%s\n' '2.1.294 (fixture)'
    exit 0
fi
printf '%s\n' "$*" >> "$CLAUDE_CALL_LOG"
case "$*" in
    'plugin marketplace list')
        printf '%s\n' "$CLAUDE_INVENTORY"
        exit "$CLAUDE_INVENTORY_STATUS"
        ;;
    'plugin marketplace add '*|'plugin marketplace update') exit 0 ;;
    'plugin install -y fixture@trailofbits')
        printf '%s\n' 'fixture plugin unavailable' >&2
        exit 91
        ;;
    *) exit 92 ;;
esac
SH
    chmod +x "$TEST_BIN/curl" "$TEST_BIN/claude"
    cp "$TEST_BIN/claude" "$INSTALL_TOOLS/bin/claude"
}

run_installer() {
    run env -i HOME="$INSTALL_HOME" PATH="$TEST_BIN:/usr/bin:/bin" \
        DF_TOOLS_ROOT="$INSTALL_TOOLS" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" \
        DF_USE_PLAT=0 CLAUDE_CONFIG_DIR="$INSTALL_HOME/.claude" \
        CLAUDE_CALL_LOG="$CLAUDE_CALL_LOG" CLAUDE_INVENTORY="$1" \
        CLAUDE_INVENTORY_STATUS="$2" bash "$INSTALL_REPO/install/claude.sh"
}

@test "Claude installer stops before plugin changes when managed settings cannot load" {
    setup_installer
    local diagnostic='Your organization requires remote managed settings to load, but they could not be loaded.'

    run_installer "$diagnostic" 1

    [ "$status" -ne 0 ]
    [ "$(cat "$CLAUDE_CALL_LOG")" = 'plugin marketplace list' ]
    [[ "$output" == *"$diagnostic"* ]]
    [[ "$output" == *"claude auth login"* ]]
}

@test "Claude installer preserves authentication rejection and gives the sign-in command" {
    setup_installer

    run_installer 'Authentication failed: HTTP 401 Unauthorized' 1

    [ "$status" -ne 0 ]
    [ "$(cat "$CLAUDE_CALL_LOG")" = 'plugin marketplace list' ]
    [[ "$output" == *'Authentication failed: HTTP 401 Unauthorized'* ]]
    [[ "$output" == *"claude auth login"* ]]
}

@test "Claude installer preserves unrelated inventory failures without recommending sign-in" {
    setup_installer

    run_installer 'Network connection timed out' 1

    [ "$status" -ne 0 ]
    [ "$(cat "$CLAUDE_CALL_LOG")" = 'plugin marketplace list' ]
    [[ "$output" == *'Network connection timed out'* ]]
    [[ "$output" != *"claude auth login"* ]]
}

@test "Claude installer reads inventory once and adds only missing marketplaces" {
    setup_installer

    run_installer $'trailofbits\nlean4-skills' 0

    # The deliberate downstream plugin failure keeps this fixture out of hooks
    # and MCP setup while proving the successful marketplace prerequisite path.
    [ "$status" -ne 0 ]
    [[ "$output" == *'fixture plugin unavailable'* ]]
    [ "$(cat "$CLAUDE_CALL_LOG")" = $'plugin marketplace list\nplugin marketplace add openai/codex-plugin-cc\nplugin marketplace add AlmogBaku/debug-skill\nplugin marketplace update\nplugin install -y fixture@trailofbits' ]
}
