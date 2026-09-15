#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export TEST_HOME="$BATS_TEST_TMPDIR/home"
    export TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_HOME/.config/dotfiles/hosts" "$TEST_BIN"
    ln -s "$REPO_ROOT" "$TEST_HOME/dotfiles"
    printf 'DF_STATE_ROOT=%s\n' "$BATS_TEST_TMPDIR/local-state" \
        > "$TEST_HOME/.config/dotfiles/hosts/$(hostname).env"
    cat > "$TEST_BIN/codex" <<'EOF'
#!/bin/sh
printf 'root=%s\n' "${CODEX_HOME:-unset}"
printf '<%s>\n' "$@"
EOF
    chmod +x "$TEST_BIN/codex"
}

render_rc() {
    local shell_name="$1" source_file
    case "$shell_name" in
        bash) source_file=dot_bashrc.tmpl ;;
        zsh) source_file=dot_zshrc.tmpl ;;
        *) return 1 ;;
    esac
    chezmoi --source "$REPO_ROOT/home" \
        --override-data '{"chezmoi":{"os":"linux"},"use_plat":false}' \
        execute-template --file "$REPO_ROOT/home/$source_file" \
        > "$BATS_TEST_TMPDIR/$shell_name-rc"
    printf '%s\n' "$BATS_TEST_TMPDIR/$shell_name-rc"
}

@test "interactive Bash and Zsh resolve host policy before the native Codex command" {
    local shell_name rendered
    for shell_name in bash zsh; do
        rendered="$(render_rc "$shell_name")"
        run env -u CODEX_HOME -u DF_STATE_ROOT -u DF_USE_PLAT -u DF_PLAT \
            HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" "$shell_name" -f -c \
            'source "$1"; type codex; codex resume "a task"' _ "$rendered"
        [ "$status" -eq 0 ]
        [[ "$output" != *'function'* ]]
        [[ "$output" == *"root=$BATS_TEST_TMPDIR/local-state/codex"* ]]
        [[ "$output" == *$'<resume>\n<a task>' ]]
    done
}

@test "interactive shell startup preserves an explicit CODEX_HOME" {
    local shell_name rendered
    for shell_name in bash zsh; do
        rendered="$(render_rc "$shell_name")"
        run env -u DF_STATE_ROOT -u DF_USE_PLAT -u DF_PLAT \
            HOME="$TEST_HOME" CODEX_HOME="$BATS_TEST_TMPDIR/explicit" \
            PATH="$TEST_BIN:$PATH" "$shell_name" -f -c \
            'source "$1"; codex doctor' _ "$rendered"
        [ "$status" -eq 0 ]
        [[ "$output" == *"root=$BATS_TEST_TMPDIR/explicit"* ]]
    done
}

@test "Codex shell templates contain no launcher wrapper" {
    ! rg -q 'codex-launch\.sh|_codex_with_host_env|^[[:space:]]*codex\(\)' \
        "$REPO_ROOT/home/dot_zshrc.tmpl" "$REPO_ROOT/home/dot_bashrc.tmpl"
    [ ! -e "$REPO_ROOT/home/.chezmoitemplates/codex-launch.sh" ]
}
