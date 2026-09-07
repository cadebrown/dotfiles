#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$TEST_HOME"
}

@test "qmd runtime check rejects an old Node launcher and child" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/_lib.sh"
        resolve_nvm_default_bin() { printf "%s\n" /runtime/v24.20.0/bin; }
        qmd_daemon_pids() { printf "%s\n" 101 102; }
        ps() {
            case "$2" in
                101) printf "%s\n" "node /runtime/v24.19.0/bin/qmd mcp --http" ;;
                102) printf "%s\n" "/runtime/v24.19.0/bin/node /runtime/v24.19.0/lib/node_modules/@tobilu/qmd/dist/cli/qmd.js mcp --http" ;;
            esac
        }
        qmd_daemon_runtime_current
    ' _ "$REPO"
    [ "$status" -ne 0 ]
}

@test "qmd runtime check accepts the current launcher and child together" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/_lib.sh"
        resolve_nvm_default_bin() { printf "%s\n" /runtime/v24.20.0/bin; }
        qmd_daemon_pids() { printf "%s\n" 101 102; }
        ps() {
            case "$2" in
                101) printf "%s\n" "node /runtime/v24.20.0/bin/qmd mcp --http" ;;
                102) printf "%s\n" "/runtime/v24.20.0/bin/node /runtime/v24.20.0/lib/node_modules/@tobilu/qmd/dist/cli/qmd.js mcp --http" ;;
            esac
        }
        qmd_daemon_runtime_current
    ' _ "$REPO"
    [ "$status" -eq 0 ]
}

@test "qmd stops its macOS LaunchAgent before replacing dependencies" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/_lib.sh"
        OS=darwin
        plutil() { return 0; }
        launchctl() { printf "%s\n" "$*" >> "$HOME/launchctl"; }
        qmd_daemon_running() { return 1; }
        qmd_daemon_stop
        cat "$HOME/launchctl"
    ' _ "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bootout gui/$(id -u)/dev.cade.qmd"* ]]
}

@test "qmd starts through launchd on macOS without creating an unmanaged daemon" {
    mkdir -p "$TEST_HOME/Library/LaunchAgents"
    touch "$TEST_HOME/Library/LaunchAgents/dev.cade.qmd.plist"
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/_lib.sh"
        OS=darwin
        plutil() { return 0; }
        has() { return 0; }
        qmd_daemon_running() { return 1; }
        qmd() { return 99; }
        launchctl() {
            printf "%s\n" "$*" >> "$HOME/launchctl"
            [[ "$1" != print ]]
        }
        qmd_daemon_start
        cat "$HOME/launchctl"
    ' _ "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enable gui/$(id -u)/dev.cade.qmd"* ]]
    [[ "$output" == *"bootstrap gui/$(id -u) $TEST_HOME/Library/LaunchAgents/dev.cade.qmd.plist"* ]]
}

@test "qmd preserves the loaded service if its on-disk plist is invalid" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 bash -c '
        source "$1/install/_lib.sh"
        OS=darwin
        plutil() { return 1; }
        launchctl() {
            [[ "$1" != bootout ]] || touch "$HOME/stopped"
        }
        qmd_daemon_stop
    ' _ "$REPO"
    [ "$status" -ne 0 ]
    [ ! -e "$TEST_HOME/stopped" ]
}
