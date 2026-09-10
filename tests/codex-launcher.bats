#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_HOME/dotfiles/install" "$TEST_HOME/.config/dotfiles/hosts" "$TEST_BIN"
    cp "$REPO_ROOT/install/_host-config.sh" "$TEST_HOME/dotfiles/install/"
    printf 'DF_STATE_ROOT=%s\n' "$BATS_TEST_TMPDIR/local-state" > "$TEST_HOME/.config/dotfiles/hosts/$(hostname).env"
    cat > "$TEST_BIN/codex" <<'EOF'
#!/bin/sh
printf 'root=%s token=%s\n' "${CODEX_HOME:-unset}" "${GH_TOKEN:-unset}"
printf '<%s>\n' "$@"
exit "${PROBE_EXIT:-0}"
EOF
    chmod +x "$TEST_BIN/codex"
}

run_launcher() {
    local shell="$1"
    shift
    run env -u CODEX_HOME -u DF_STATE_ROOT -u DF_USE_PLAT -u DF_PLAT \
        HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" GH_TOKEN=fixture-token \
        "$shell" -c '. "$1"; shift; _codex_with_host_env "$@"' \
        _ "$REPO_ROOT/home/.chezmoitemplates/codex-launch.sh" "$@"
}

@test "Codex launch resolves host policy in non-login Bash and Zsh" {
    local shell
    for shell in bash zsh; do
        run_launcher "$shell" resume 'a task' --last
        [ "$status" -eq 0 ]
        [ "$output" = "root=$BATS_TEST_TMPDIR/local-state/codex token=fixture-token"$'\n<resume>\n<a task>\n<--last>' ]
    done
}

@test "Codex launch preserves explicit runtime and does not leak policy into its shell" {
    local shell
    for shell in bash zsh; do
        run env -u DF_STATE_ROOT HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" GH_TOKEN=fixture-token \
            CODEX_HOME="$BATS_TEST_TMPDIR/explicit" "$shell" -c \
            '. "$1"; _codex_with_host_env doctor; printf "policy=%s\n" "${DF_STATE_ROOT:-unset}"' \
            _ "$REPO_ROOT/home/.chezmoitemplates/codex-launch.sh"
        [ "$status" -eq 0 ]
        [ "$output" = "root=$BATS_TEST_TMPDIR/explicit token=fixture-token"$'\n<doctor>\npolicy=unset' ]
    done
}

@test "Codex launch rejects invalid host data before invoking the binary" {
    printf 'DF_USE_PLAT=invalid\n' > "$TEST_HOME/.config/dotfiles/hosts/$(hostname).env"
    local shell
    for shell in bash zsh; do
        run_launcher "$shell" doctor
        [ "$status" -ne 0 ]
        [[ "$output" != *'root='* ]]
        [[ "$output" == *'Invalid host configuration'* ]]
    done
}

@test "Codex launch honors invocation override after a login already resolved policy" {
    local shell
    for shell in bash zsh; do
        run env -u CODEX_HOME -u DF_STATE_ROOT HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" GH_TOKEN=fixture-token \
            "$shell" -c '. "$HOME/dotfiles/install/_host-config.sh"; _host_config_resolve "$HOME/dotfiles"; . "$1"; CODEX_HOME=/explicit-after-login _codex_with_host_env doctor' \
            _ "$REPO_ROOT/home/.chezmoitemplates/codex-launch.sh"
        [ "$status" -eq 0 ]
        [[ "$output" == 'root=/explicit-after-login token=fixture-token'* ]]
    done
}

@test "Codex launch keeps the ordinary home fallback and command exit status" {
    printf '# No override\n' > "$TEST_HOME/.config/dotfiles/hosts/$(hostname).env"
    local shell
    for shell in bash zsh; do
        PROBE_EXIT=23 run_launcher "$shell" doctor
        [ "$status" -eq 23 ]
        [[ "$output" == 'root=unset token=fixture-token'* ]]
    done
}
