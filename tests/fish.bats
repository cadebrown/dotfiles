#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FISH_BIN="$(command -v fish)"
    TEST_HOME="$BATS_TEST_TMPDIR/fish home"
    mkdir -p "$TEST_HOME/.config/fish/conf.d" "$TEST_HOME/.local/bin"
    ln -s "$REPO" "$TEST_HOME/dotfiles"
    cp "$REPO/home/dot_config/fish/conf.d/00-dotfiles-env.fish" \
        "$TEST_HOME/.config/fish/conf.d/00-dotfiles-env.fish"
}

render_bridge() {
    local use_plat="$1"
    chezmoi --source "$REPO/home" \
        --override-data "{\"chezmoi\":{\"os\":\"linux\"},\"use_plat\":$use_plat}" \
        execute-template --file "$REPO/home/dot_config/fish/conf.d/dotfiles-env-bridge.bash.tmpl" \
        > "$TEST_HOME/.config/fish/conf.d/dotfiles-env-bridge.bash"
    chmod +x "$TEST_HOME/.config/fish/conf.d/dotfiles-env-bridge.bash"
}

write_profile_fixture() {
    chezmoi --source "$REPO/home" \
        --override-data '{"chezmoi":{"os":"linux"}}' \
        execute-template --file "$REPO/home/dot_profile.tmpl" > "$TEST_HOME/.profile"
    cat >> "$TEST_HOME/.profile" <<'EOF'
export EDITOR='fish editor
second line'
EOF
}

write_node_fixture() {
    local local_root="$1"
    mkdir -p "$local_root/nvm/alias" "$local_root/nvm/versions/node/v22.14.0/bin"
    printf '%s\n' '22' > "$local_root/nvm/alias/default"
}

fish_env() {
    env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin USER=test LOGNAME=test \
        "$FISH_BIN" -l -c "$1"
}

@test "Fish login config supplies the flat managed runtime roots without losing spaces or newlines" {
    render_bridge false
    write_profile_fixture
    write_node_fixture "$TEST_HOME/.local"

    run fish_env 'printf "%s\n" "$DF_USE_PLAT|$_LOCAL_PLAT|$NVM_DIR|$CARGO_HOME|$ELAN_HOME|$UV_TOOL_DIR|$GOPATH|$JULIA_DEPOT_PATH"; string escape -- "$EDITOR"; string join : -- $PATH'

    [ "$status" -eq 0 ]
    [[ "$output" == *"0|$TEST_HOME/.local|$TEST_HOME/.local/nvm|$TEST_HOME/.local/cargo|$TEST_HOME/.local/elan|$TEST_HOME/.local/uv/tools|$TEST_HOME/.local/go|$TEST_HOME/.local/julia/depot"* ]]
    [[ "$output" == *"fish\\ editor\\nsecond\\ line"* ]]
    [[ "$output" == *"$TEST_HOME/.local/nvm/versions/node/v22.14.0/bin:$TEST_HOME/.local/elan/bin:$TEST_HOME/.local/cargo/bin:$TEST_HOME/.local/bin:"* ]]
}

@test "Fish PLAT layout uses the detected root and default Node precedes a Homebrew Node" {
    local plat
    plat="$(env HOME="$TEST_HOME" bash -c 'source "$HOME/dotfiles/install/_runtime-paths.sh"; DF_USE_PLAT=1; _normalize_plat_layout; _detect_plat "$HOME/dotfiles"; printf %s "$PLAT"')"
    [ -n "$plat" ]
    render_bridge true
    write_profile_fixture
    write_node_fixture "$TEST_HOME/.local/$plat"
    mkdir -p "$TEST_HOME/.local/$plat/brew/bin"
    cat > "$TEST_HOME/.local/$plat/brew/bin/brew" <<EOF
#!/bin/sh
if [ "\$1" = shellenv ]; then
    printf '%s\\n' 'export HOMEBREW_PREFIX="$TEST_HOME/.local/$plat/brew"'
    printf '%s\\n' 'export PATH="$TEST_HOME/.local/$plat/brew/bin:\$PATH"'
fi
EOF
    chmod +x "$TEST_HOME/.local/$plat/brew/bin/brew"

    run fish_env 'printf "%s\n" "$DF_USE_PLAT|$_PLAT|$_LOCAL_PLAT|$UV_TOOL_BIN_DIR|$HOMEBREW_PREFIX"; string join : -- $PATH'

    [ "$status" -eq 0 ]
    [[ "$output" == *"1|$plat|$TEST_HOME/.local/$plat|$TEST_HOME/.local/$plat/bin|$TEST_HOME/.local/$plat/brew"* ]]
    [[ "$output" == *"$TEST_HOME/.local/$plat/nvm/versions/node/v22.14.0/bin"* ]]
    [[ "$output" == *"$TEST_HOME/.local/$plat/nvm/versions/node/v22.14.0/bin"*"$TEST_HOME/.local/$plat/brew/bin"* ]]
}

@test "Fish keeps an activated virtualenv first and does not grow PATH on nested login shells" {
    render_bridge false
    write_profile_fixture
    write_node_fixture "$TEST_HOME/.local"
    mkdir -p "$TEST_HOME/project/.venv/bin"

    run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin USER=test LOGNAME=test \
        VIRTUAL_ENV="$TEST_HOME/project/.venv" "$FISH_BIN" -l -c "$FISH_BIN -l -c 'string join : -- \$PATH'"

    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_HOME/project/.venv/bin:"* ]]
    [ "$(tr ':' '\n' <<< "$output" | sort | uniq -d | wc -l | tr -d ' ')" -eq 0 ]
}

@test "nested Fish preserves the shared profile guard without appending build flags twice" {
    render_bridge false
    write_profile_fixture
    cat >> "$TEST_HOME/.profile" <<'EOF'
export LDFLAGS="${LDFLAGS:+$LDFLAGS }-Wl,fixture"
EOF

    run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin USER=test LOGNAME=test \
        "$FISH_BIN" -l -c "$FISH_BIN -l -c 'printf \"%s\\n\" \"\$LDFLAGS\"'"

    [ "$status" -eq 0 ]
    [ "$output" = '-Wl,fixture' ]
}

@test "Fish imports unified cache defaults and preserves an explicit Rust bypass" {
    render_bridge false
    write_profile_fixture
    printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.local/bin/sccache"
    chmod +x "$TEST_HOME/.local/bin/sccache"

    run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin USER=test LOGNAME=test \
        RUSTC_WRAPPER= SCCACHE_CACHE_SIZE=31G "$FISH_BIN" -l -c \
        'printf "%s\n" "$CMAKE_C_COMPILER_LAUNCHER|$CMAKE_CXX_COMPILER_LAUNCHER|$CMAKE_CUDA_COMPILER_LAUNCHER|$RUSTC_WRAPPER|$SCCACHE_CACHE_SIZE"; set --query CCACHE_SLOPPINESS; or echo no-ccache-policy'

    [ "$status" -eq 0 ]
    [ "$output" = $'sccache|sccache|sccache||31G\nno-ccache-policy' ]
}

@test "Fish erases inherited disabled bytecode caching and retired ccache settings" {
    render_bridge false
    write_profile_fixture
    printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.local/bin/sccache"
    chmod +x "$TEST_HOME/.local/bin/sccache"
    mkdir -p "$TEST_HOME/.config/sccache"
    printf '[cache.disk]\nsize = 268435456000\n' > "$TEST_HOME/.config/sccache/config"

    run env -i HOME="$TEST_HOME" PATH=/usr/bin:/bin USER=test LOGNAME=test \
        _PROFILE_SOURCED=1 CCACHE_SLOPPINESS=file_stat_matches,time_macros CCACHE_HARDLINK=1 \
        CMAKE_CXX_COMPILER_LAUNCHER=ccache SCCACHE_CACHE_SIZE=74G PYTHONDONTWRITEBYTECODE=1 \
        "$FISH_BIN" -l -c \
        'printf "%s\n" "$CMAKE_CXX_COMPILER_LAUNCHER|$SCCACHE_CONF|$PYTHONPYCACHEPREFIX"; for name in PYTHONDONTWRITEBYTECODE CCACHE_HARDLINK SCCACHE_CACHE_SIZE; if set --query $name; echo unexpected-$name; end; end; true'
    [ "$status" -eq 0 ]
    [ "$output" = "sccache|$TEST_HOME/.config/sccache/config|$TEST_HOME/.cache/python/pycache" ]
}
