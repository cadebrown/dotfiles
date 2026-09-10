#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    FAKE_REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE_HOME/.config/dotfiles" "$FAKE_REPO"
    for directory in install home packages; do
        ln -s "$REPO/$directory" "$FAKE_REPO/$directory"
    done
    HOST_FILE="$FAKE_HOME/.config/dotfiles/hosts/$(hostname).env"
    mkdir -p "${HOST_FILE%/*}"
    FLAT="$FAKE_HOME/.local"
    ISOLATED="$(env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_USE_PLAT=1 \
        /bin/bash -es -- "$FAKE_REPO" <<'SH'
source "$1/install/_lib.sh"
printf '%s' "$LOCAL_PLAT"
SH
    )"
}

set_host_layout() { printf 'DF_USE_PLAT=%s\n' "$1" > "$HOST_FILE"; }

write_runtimes() {
    local directory="$1" executable
    mkdir -p "$directory/bin" "$directory/python/bin"
    for executable in "$directory/bin/uv" "$directory/python/bin/python"; do
        cat > "$executable" <<'SH'
#!/bin/sh
printf 'runtime=%s\ncache=%s\n' "$0" "${UV_CACHE_DIR:-}"
printf 'arg=%s\n' "$@"
SH
        chmod +x "$executable"
    done
}

install_helpers() {
    run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" \
        "$@" /bin/bash "$FAKE_REPO/install/agent-tools.sh"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}

check_launchers() {
    local directory="$1" cache="$2"
    shift 2
    run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" \
        "$@" "$FAKE_HOME/.local/bin/df-google-mcp" https://run.googleapis.com/mcp
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "runtime=$directory/bin/uv" ]
    [ "${lines[1]}" = "cache=$cache" ]
    [ "${lines[2]}" = "arg=--quiet" ]
    [ "${lines[3]}" = "arg=run" ]
    [ "${lines[4]}" = "arg=--locked" ]
    [ "${lines[5]}" = "arg=--script" ]
    [ "${lines[6]}" = "arg=$FAKE_REPO/install/google-mcp.py" ]
    [ "${lines[7]}" = "arg=https://run.googleapis.com/mcp" ]

    run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" \
        "$@" "$FAKE_HOME/.local/bin/df-task" status fixture-task
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "runtime=$directory/python/bin/python" ]
    [ "${lines[2]}" = "arg=$FAKE_HOME/.local/lib/dotfiles/df_task.py" ]
    [ "${lines[3]}" = "arg=status" ]
    [ "${lines[4]}" = "arg=fixture-task" ]
}

@test "minimal GUI environment deploys and launches flat runtimes from host policy" {
    set_host_layout 0
    write_runtimes "$FLAT"
    install_helpers
    check_launchers "$FLAT" "$FLAT/uv/cache"
    install_helpers
    check_launchers "$FLAT" "$FLAT/uv/cache"
}

@test "minimal GUI environment deploys and launches PLAT runtimes without flat uv" {
    set_host_layout 1
    write_runtimes "$ISOLATED"
    install_helpers
    [ ! -e "$FLAT/bin/uv" ]
    [ -x "$ISOLATED/bin/df-google-mcp" ]
    [ -x "$ISOLATED/bin/df-task" ]
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache"
    install_helpers
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache"
}

@test "explicit layout overrides host policy for installer and launched runtimes" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    set_host_layout 0
    install_helpers DF_USE_PLAT=1
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache" DF_USE_PLAT=1
    check_launchers "$FLAT" "$FLAT/uv/cache" DF_USE_PLAT=0
    install_helpers DF_USE_PLAT=0
}

@test "absent host policy preserves flat default and explicit cache directory" {
    write_runtimes "$FLAT"
    install_helpers
    check_launchers "$FLAT" "$FLAT/uv/cache"
    check_launchers "$FLAT" "$FAKE_HOME/custom-cache" UV_CACHE_DIR="$FAKE_HOME/custom-cache"
}

@test "host policy accepts a final digit without a newline" {
    printf 'DF_USE_PLAT=1' > "$HOST_FILE"
    write_runtimes "$ISOLATED"
    install_helpers
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache"
}

@test "malformed host policy stops installer and launchers before a runtime executes" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    install_helpers
    local value command
    for value in 'broken' '' $'1\nbroken'; do
        printf 'DF_USE_PLAT=%s\n' "$value" > "$HOST_FILE"
        for command in "$FAKE_REPO/install/agent-tools.sh" \
                "$FAKE_HOME/.local/bin/df-google-mcp" "$FAKE_HOME/.local/bin/df-task"; do
            run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" \
                /bin/bash "$command" --check-runtime
            printf '%s\n' "$output"
            [ "$status" -ne 0 ]
            [[ "$output" != *runtime=* ]]
            [[ "$(cat "$HOST_FILE")" == *"$value"* ]]
        done
    done
}

@test "task runtime preserves caller environment and never sources installer credentials" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    install_helpers
    printf 'exit 27\n' > "$FAKE_HOME/.unrelated.env"
    local directory layout
    for layout in 0 1; do
        directory="$FLAT"
        [[ "$layout" == 1 ]] && directory="$ISOLATED"
        cat > "$directory/python/bin/python" <<'SH'
#!/bin/sh
printf 'git=%s\ncflags=%s\nrustflags=%s\npath=%s\n' "${GIT_CONFIG_GLOBAL:-unset}" "${CFLAGS:-unset}" "${RUSTFLAGS:-unset}" "$PATH"
printf 'arg=%s\n' "$@"
SH
        set_host_layout "$layout"
        run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" \
            GIT_CONFIG_GLOBAL="$FAKE_HOME/custom-git-config" \
            "$FAKE_HOME/.local/bin/df-task" checkpoint --note 'literal $PATH and spaces'
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "git=$FAKE_HOME/custom-git-config" ]
        [ "${lines[1]}" = 'cflags=unset' ]
        [ "${lines[2]}" = 'rustflags=unset' ]
        [ "${lines[3]}" = 'path=/usr/bin:/bin' ]
        [ "${lines[7]}" = 'arg=literal $PATH and spaces' ]
    done
}

@test "runtime paths follow relocated local symlinks in both layouts" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    install_helpers
    local scratch="$BATS_TEST_TMPDIR/scratch" relocated="$BATS_TEST_TMPDIR/moved scratch" layout directory
    mv "$FLAT" "$scratch"
    scratch="$(cd "$scratch" && pwd -P)"
    ln -s "$scratch" "$FLAT"
    for layout in 0 1; do
        directory="$scratch"
        [[ "$layout" == 1 ]] && directory="$scratch/${ISOLATED##*/}"
        check_launchers "$directory" "$directory/uv/cache" DF_USE_PLAT="$layout"
    done
    mv "$scratch" "$relocated"
    relocated="$(cd "$relocated" && pwd -P)"
    rm "$FLAT"
    ln -s "$relocated" "$FLAT"
    for layout in 0 1; do
        directory="$relocated"
        [[ "$layout" == 1 ]] && directory="$relocated/${ISOLATED##*/}"
        check_launchers "$directory" "$directory/uv/cache" DF_USE_PLAT="$layout"
    done
}

@test "task launcher rejects missing selected runtime without using another Python" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    install_helpers
    rm "$ISOLATED/python/bin/python"
    run env -i HOME="$FAKE_HOME" PATH="$FLAT/python/bin:/usr/bin:/bin" \
        DF_DOTFILES_REPO="$FAKE_REPO" DF_USE_PLAT=1 "$FAKE_HOME/.local/bin/df-task" list
    [ "$status" -ne 0 ]
    [[ "$output" == *'Run install/python.sh before using df-task'* ]]
    [[ "$output" != *runtime=* ]]
}

@test "runtime resolver and installer agree on accepted explicit layout values" {
    local value expected
    for value in 0 1 true yes on TRUE YES ON false unknown ''; do
        expected="$(env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_USE_PLAT="$value" \
            /bin/bash -ec 'source "$1/install/_lib.sh"; printf "%s" "$LOCAL_PLAT"' fixture "$FAKE_REPO")"
        run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_USE_PLAT="$value" \
            /bin/bash -ec 'source "$1/install/agent-runtime.sh" --runtime-only; printf "%s" "$LOCAL_PLAT"' fixture "$FAKE_REPO"
        [ "$status" -eq 0 ]
        [ "$output" = "$expected" ]
    done
}

@test "runtime requires a matching host specification only in PLAT layout" {
    local minimal_repo="$BATS_TEST_TMPDIR/minimal"
    mkdir -p "$minimal_repo/install"
    cp "$REPO/install/agent-runtime.sh" "$REPO/install/_runtime-paths.sh" "$REPO/install/_host-config.sh" "$minimal_repo/install/"
    run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_USE_PLAT=0 \
        /bin/bash -ec 'source "$1/install/agent-runtime.sh" --runtime-only; printf "%s" "$PYTHON_ENV"' fixture "$minimal_repo"
    [ "$status" -eq 0 ]
    [ "$output" = "$FLAT/python" ]
    run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_USE_PLAT=1 PLAT=stale-host \
        /bin/bash -ec 'source "$1/install/agent-runtime.sh" --runtime-only' fixture "$minimal_repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'no matching plat spec'* ]]
}

@test "Google runtime retains uv isolation without sourcing installer credentials" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    install_helpers
    printf 'exit 27\n' > "$FAKE_HOME/.unrelated.env"
    local directory layout
    for layout in 0 1; do
        directory="$FLAT"
        [[ "$layout" == 1 ]] && directory="$ISOLATED"
        cat > "$directory/bin/uv" <<'SH'
#!/bin/sh
printf 'python=%s\ntools=%s\nbin=%s\n' "$UV_PYTHON_INSTALL_DIR" "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR"
printf 'arg=%s\n' "$@"
SH
        run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" DF_USE_PLAT="$layout" \
            "$FAKE_HOME/.local/bin/df-google-mcp" https://run.googleapis.com/mcp
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "python=$directory/uv/python" ]
        [ "${lines[1]}" = "tools=$directory/uv/tools" ]
        [ "${lines[2]}" = "bin=$directory/bin" ]
        [ "${lines[8]}" = 'arg=https://run.googleapis.com/mcp' ]
    done
}
