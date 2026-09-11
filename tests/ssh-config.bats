#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURE="$BATS_TEST_TMPDIR/repo with spaces"
    mkdir -p "$FIXTURE/home" "$BATS_TEST_TMPDIR/user/.ssh/config.d"
    local chezmoi_bin="${CHEZMOI_BIN:-$(command -v chezmoi)}"
    "$chezmoi_bin" --config /dev/null --config-format toml --source "$FIXTURE/home" execute-template \
        < "$REPO_ROOT/home/dot_ssh/config.tmpl" > "$BATS_TEST_TMPDIR/rendered"
    # OpenSSH expands ~ from the account database, not HOME. Isolate the local
    # include so fixtures never consume the real user's SSH configuration.
    sed "s|~/.ssh/|$BATS_TEST_TMPDIR/user/.ssh/|g" "$BATS_TEST_TMPDIR/rendered" \
        > "$BATS_TEST_TMPDIR/config"
}

forwarding_is() {
    local host="$1" expected="$2"
    run ssh -G -F "$BATS_TEST_TMPDIR/config" "$host"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n'"forwardagent $expected"* ]]
}

@test "SSH defaults to no forwarding without an overlay" {
    forwarding_is unrelated.example no
}

@test "SSH reads private overlay host blocks without enabling other hosts" {
    mkdir -p "$FIXTURE/dotfiles-work/ssh"
    printf 'Host trusted trusted.example\n    ForwardAgent yes\n' \
        > "$FIXTURE/dotfiles-work/ssh/config"
    forwarding_is trusted yes
    forwarding_is trusted.example yes
    forwarding_is unrelated.example no
    forwarding_is trusted.example.evil no
}

@test "SSH local overrides win and do not scope out later overlay includes" {
    mkdir -p "$FIXTURE/dotfiles-work/ssh"
    printf 'Host trusted other\n    ForwardAgent yes\n' \
        > "$FIXTURE/dotfiles-work/ssh/config"
    printf 'Host trusted\n    ForwardAgent no\nHost unrelated\n    User nobody\n' \
        > "$BATS_TEST_TMPDIR/user/.ssh/config.d/00-local"
    forwarding_is trusted no
    forwarding_is other yes
    forwarding_is unrelated.example no
}

@test "SSH overlay order is lexical and an absent overlay returns to safe defaults" {
    mkdir -p "$FIXTURE/dotfiles-a/ssh" "$FIXTURE/dotfiles-z/ssh"
    printf 'Host trusted\n    ForwardAgent no\n' > "$FIXTURE/dotfiles-a/ssh/config"
    printf 'Host trusted\n    ForwardAgent yes\n' > "$FIXTURE/dotfiles-z/ssh/config"
    forwarding_is trusted no
    mv "$FIXTURE/dotfiles-a/ssh/config" "$FIXTURE/dotfiles-a/ssh/config.disabled"
    forwarding_is trusted yes
    mv "$FIXTURE/dotfiles-z/ssh/config" "$FIXTURE/dotfiles-z/ssh/config.disabled"
    forwarding_is trusted no
}

@test "SSH wildcard overlay opts in every destination but local opt-outs win" {
    mkdir -p "$FIXTURE/dotfiles-work/ssh"
    printf 'Host *\n    ForwardAgent yes\n' > "$FIXTURE/dotfiles-work/ssh/config"
    local host
    for host in trusted trusted.example unrelated.example 192.0.2.1; do
        forwarding_is "$host" yes
    done
    printf 'Host unrelated.example\n    ForwardAgent no\n' \
        > "$BATS_TEST_TMPDIR/user/.ssh/config.d/00-local"
    forwarding_is unrelated.example no
    forwarding_is trusted yes
    run ssh -a -G -F "$BATS_TEST_TMPDIR/config" trusted
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\nforwardagent no'* ]]
    mv "$FIXTURE/dotfiles-work/ssh/config" "$FIXTURE/dotfiles-work/ssh/config.disabled"
    forwarding_is trusted no
}
