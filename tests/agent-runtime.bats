#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    FAKE_REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE_HOME/.config/dotfiles" "$FAKE_REPO"
    for directory in install home packages; do
        ln -s "$REPO/$directory" "$FAKE_REPO/$directory"
    done
    MARKER="$FAKE_HOME/.config/dotfiles/agent-layout"
    FLAT="$FAKE_HOME/.local"
    ISOLATED="$(env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_USE_PLAT=1 \
        /bin/bash -es -- "$FAKE_REPO" <<'SH'
source "$1/install/_lib.sh"
printf '%s' "$LOCAL_PLAT"
SH
    )"
}

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

@test "minimal GUI environment deploys and launches flat runtimes from persisted layout" {
    printf '0\n' > "$MARKER"
    write_runtimes "$FLAT"
    install_helpers
    [ "$(cat "$MARKER")" = 0 ]
    check_launchers "$FLAT" "$FLAT/uv/cache"
    install_helpers
    check_launchers "$FLAT" "$FLAT/uv/cache"
}

@test "minimal GUI environment deploys and launches PLAT runtimes without flat uv" {
    printf '1\n' > "$MARKER"
    write_runtimes "$ISOLATED"
    install_helpers
    [ "$(cat "$MARKER")" = 1 ]
    [ ! -e "$FLAT/bin/uv" ]
    [ -x "$ISOLATED/bin/df-google-mcp" ]
    [ -x "$ISOLATED/bin/df-task" ]
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache"
    install_helpers
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache"
}

@test "explicit layout overrides persisted state for installer and launched runtimes" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    printf '0\n' > "$MARKER"
    install_helpers DF_USE_PLAT=1
    [ "$(cat "$MARKER")" = 1 ]
    printf '0\n' > "$MARKER"
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache" DF_USE_PLAT=1
    printf '1\n' > "$MARKER"
    check_launchers "$FLAT" "$FLAT/uv/cache" DF_USE_PLAT=0
    install_helpers DF_USE_PLAT=0
    [ "$(cat "$MARKER")" = 0 ]
}

@test "absent layout marker preserves flat default and explicit cache directory" {
    write_runtimes "$FLAT"
    install_helpers
    [ "$(cat "$MARKER")" = 0 ]
    rm "$MARKER"
    check_launchers "$FLAT" "$FLAT/uv/cache"
    check_launchers "$FLAT" "$FAKE_HOME/custom-cache" UV_CACHE_DIR="$FAKE_HOME/custom-cache"
}

@test "layout marker accepts a final digit without a newline" {
    printf 1 > "$MARKER"
    write_runtimes "$ISOLATED"
    install_helpers
    printf 1 > "$MARKER"
    check_launchers "$ISOLATED" "$ISOLATED/uv/cache"
}

@test "malformed layout stops installer and launchers before a runtime executes" {
    write_runtimes "$FLAT"
    write_runtimes "$ISOLATED"
    install_helpers
    local value command
    for value in 'broken' '' $'1\nbroken'; do
        printf '%s\n' "$value" > "$MARKER"
        for command in "$FAKE_REPO/install/agent-tools.sh" \
                "$FAKE_HOME/.local/bin/df-google-mcp" "$FAKE_HOME/.local/bin/df-task"; do
            run env -i HOME="$FAKE_HOME" PATH=/usr/bin:/bin DF_DOTFILES_REPO="$FAKE_REPO" \
                /bin/bash "$command" --check-runtime
            printf '%s\n' "$output"
            [ "$status" -ne 0 ]
            [[ "$output" != *runtime=* ]]
            [ "$(cat "$MARKER")" = "$value" ]
        done
    done
}
