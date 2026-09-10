#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    test_home="$BATS_TEST_TMPDIR/home with spaces"
    mkdir -p "$test_home/.local/nvm/alias/lts" "$test_home/dotfiles/install"
    cp "$REPO/install/_host-config.sh" "$REPO/install/_runtime-paths.sh" "$test_home/dotfiles/install/"
}

write_host_policy() {
    mkdir -p "$test_home/.config/dotfiles/hosts"
    printf 'DF_USE_PLAT=%s\nDF_PLAT=%s\n' "$1" "${2:-auto}" \
        > "$test_home/.config/dotfiles/hosts/$(hostname).env"
}

run_partial() {
    local shell_name="$1" partial="$2" assertions="$3"
    run env HOME="$test_home" "$shell_name" -c \
        'export NVM_DIR="$HOME/.local/nvm"; source "$1"; eval "$2"' \
        _ "$REPO/home/.chezmoitemplates/$partial" "$assertions"
    [ "$status" -eq 0 ]
}

@test "Node login selection uses numeric order and honors exact and minor aliases" {
    mkdir -p "$test_home/.local/nvm/versions/node/"v{24.9.1,24.10.1,24.10.2,25.0.0}/bin
    for shell_name in bash zsh; do
        printf '24\n' > "$test_home/.local/nvm/alias/default"
        run_partial "$shell_name" nvm-default.sh '[[ "$_nvm_default_dir" == */v24.10.2 ]]'
        printf 'v24.10.1\n' > "$test_home/.local/nvm/alias/default"
        run_partial "$shell_name" nvm-default.sh '[[ "$_nvm_default_dir" == */v24.10.1 ]]'
        printf '24.9\n' > "$test_home/.local/nvm/alias/default"
        run_partial "$shell_name" nvm-default.sh '[[ "$_nvm_default_dir" == */v24.9.1 ]]'
    done
}

@test "Node aliases follow LTS and custom chains and refresh after installs" {
    mkdir -p "$test_home/.local/nvm/versions/node/v24.10.1/bin"
    printf '# default\nteam # shared alias\n' > "$test_home/.local/nvm/alias/default"
    printf 'lts/*\n' > "$test_home/.local/nvm/alias/team"
    printf '24\n' > "$test_home/.local/nvm/alias/lts/*"
    for shell_name in bash zsh; do
        run_partial "$shell_name" nvm-default.sh '[[ "$_nvm_default_dir" == */v24.10.1 ]]'
    done
    mkdir -p "$test_home/.local/nvm/versions/node/v24.10.2/bin"
    for shell_name in bash zsh; do
        run_partial "$shell_name" nvm-default.sh '[[ "$_nvm_default_dir" == */v24.10.2 ]]'
    done
}

@test "Node selection safely handles missing installs and cyclic aliases" {
    for shell_name in bash zsh; do
        run_partial "$shell_name" nvm-default.sh '[[ -z "$_nvm_default_dir" ]]'
        printf 'team\n' > "$test_home/.local/nvm/alias/default"
        printf 'default\n' > "$test_home/.local/nvm/alias/team"
        run_partial "$shell_name" nvm-default.sh '[[ -z "$_nvm_default_dir" ]]'
    done
}

@test "PLAT detection checks highest first and refreshes capability changes" {
    local spec_root="$test_home/dotfiles/install/plat"
    mkdir -p "$spec_root/plat_Linux_x-v2" "$spec_root/plat_Linux_x-v3"
    printf 'exit 0\n' > "$spec_root/plat_Linux_x-v2/.plat_check.sh"
    printf 'exit 1\n' > "$spec_root/plat_Linux_x-v3/.plat_check.sh"
    for shell_name in bash zsh; do
        run env HOME="$test_home" "$shell_name" -c \
            'OSTYPE=linux-gnu; source "$1"; [[ "$_PLAT_DETECTED" == plat_Linux_x-v2 ]]' \
            _ "$REPO/home/.chezmoitemplates/plat-detect.sh"
        [ "$status" -eq 0 ]
    done
    printf 'exit 0\n' > "$spec_root/plat_Linux_x-v3/.plat_check.sh"
    for shell_name in bash zsh; do
        run env HOME="$test_home" "$shell_name" -c \
            'OSTYPE=linux-gnu; source "$1"; [[ "$_PLAT_DETECTED" == plat_Linux_x-v3 ]]' \
            _ "$REPO/home/.chezmoitemplates/plat-detect.sh"
        [ "$status" -eq 0 ]
    done
}

@test "rendered profiles initialize fresh environment and invoke brew once with their shell" {
    mkdir -p "$test_home/.homebrew/bin" "$test_home/.local/nvm/versions/node/v24.10.1/bin"
    printf '24\n' > "$test_home/.local/nvm/alias/default"
    printf 'export PROFILE_FIXTURE=loaded\n' > "$test_home/.profile"
    printf 'export CREDENTIAL_FIXTURE=fresh\n' > "$test_home/.work.env"
    cat > "$test_home/.homebrew/bin/brew" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/brew-calls"
printf 'export HOMEBREW_PREFIX="%s/.homebrew"\n' "$HOME"
EOF
    chmod +x "$test_home/.homebrew/bin/brew"
    write_host_policy 0
    for shell_name in bash zsh; do
        local source_file=dot_bash_profile.tmpl
        [[ "$shell_name" == zsh ]] && source_file=dot_zprofile.tmpl
        local rendered="$BATS_TEST_TMPDIR/$shell_name-profile"
        chezmoi --source "$REPO/home" \
            --override-data '{"chezmoi":{"os":"darwin"}}' \
            execute-template --file "$REPO/home/$source_file" > "$rendered"
        run env -i HOME="$test_home" PATH=/usr/bin:/bin SSH_AUTH_SOCK=fixture \
            "$(command -v "$shell_name")" -c 'source "$1"; [[ "$PROFILE_FIXTURE" == loaded && "$CREDENTIAL_FIXTURE" == fresh && "$NVM_DIR" == "$HOME/.local/nvm" && "$HOMEBREW_PREFIX" == "$HOME/.homebrew" && "$PATH" == *"/v24.10.1/bin"* ]]' _ "$rendered"
        [ "$status" -eq 0 ]
    done
    [ "$(cat "$test_home/brew-calls")" = $'shellenv bash\nshellenv zsh' ]
}

@test "rendered PLAT profiles resolve relocated installs and source current spec exports" {
    local storage="$BATS_TEST_TMPDIR/storage"
    local spec=plat_Linux_fixture
    mkdir -p "$storage/$spec/nvm/alias" "$storage/$spec/nvm/versions/node/v24.10.1/bin" \
        "$test_home/dotfiles/install/plat/$spec"
    storage="$(cd "$storage" && pwd -P)"
    # setup created an empty flat nvm fixture; move it aside before relocation.
    mv "$test_home/.local" "$test_home/old-local"
    ln -s "$storage" "$test_home/.local"
    printf '24\n' > "$storage/$spec/nvm/alias/default"
    printf 'exit 0\n' > "$test_home/dotfiles/install/plat/$spec/.plat_check.sh"
    printf 'export SPEC_FIXTURE=current\n' > "$test_home/dotfiles/install/plat/$spec/.plat_env.sh"
    : > "$test_home/.profile"
    write_host_policy 1 "$spec"
    for shell_name in bash zsh; do
        local source_file=dot_bash_profile.tmpl
        [[ "$shell_name" == zsh ]] && source_file=dot_zprofile.tmpl
        local rendered="$BATS_TEST_TMPDIR/$shell_name-profile"
        chezmoi --source "$REPO/home" \
            --override-data '{"chezmoi":{"os":"darwin"}}' \
            execute-template --file "$REPO/home/$source_file" > "$rendered"
        run env -i HOME="$test_home" PATH=/usr/bin:/bin SSH_AUTH_SOCK=fixture \
            "$(command -v "$shell_name")" -c 'OSTYPE=linux-gnu; source "$1"; [[ "$DF_USE_PLAT" == 1 && "$SPEC_FIXTURE" == current && "$_LOCAL_PLAT" == "$2/plat_Linux_fixture" && "$PATH" == *"/v24.10.1/bin"* ]]' _ "$rendered" "$storage"
        [ "$status" -eq 0 ]
    done
}
