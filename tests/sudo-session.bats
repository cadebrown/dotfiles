#!/usr/bin/env bats
# Sudo timestamps follow the installed policy. Exercise the helper with a mock so
# the behavior is deterministic on Linux CI and never touches the host ticket.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # These fixtures simulate macOS on Linux too; the container's PLAT-on
    # bootstrap must not require a native Darwin spec for its Linux CPU name.
    export DF_USE_PLAT=0
    FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
    mkdir -p "$FAKE_BIN"

    cat > "$FAKE_BIN/uname" <<'SH'
#!/bin/sh
if [ "${1:-}" = -s ]; then printf '%s\n' "${DF_FIXTURE_OS:-Darwin}"; else exec /usr/bin/uname "$@"; fi
SH
    cat > "$FAKE_BIN/sudo" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$SUDO_LOG"
case "$*" in
    '-v') [ "${SUDO_FAIL_FOREGROUND:-0}" != 1 ] ;;
    '-n -v')
        attempts=0
        if [ -n "${SUDO_ATTEMPTS:-}" ] && [ -f "$SUDO_ATTEMPTS" ]; then attempts="$(cat "$SUDO_ATTEMPTS")"; fi
        attempts=$((attempts + 1))
        [ -z "${SUDO_ATTEMPTS:-}" ] || printf '%s\n' "$attempts" > "$SUDO_ATTEMPTS"
        [ "${SUDO_FAIL_NONINTERACTIVE:-0}" != 1 ] && \
            { [ -z "${SUDO_FAIL_NONINTERACTIVE_AFTER:-}" ] || [ "$attempts" -lt "$SUDO_FAIL_NONINTERACTIVE_AFTER" ]; }
        ;;
esac
SH
    chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/sudo"
}

run_helper() {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" REPO="$REPO" \
        bash -c "$1"
}

@test "interactive macOS authenticates once and reaps its keeper" {
    run_helper '
        source "$REPO/install/_lib.sh"
        _sudo_session_interactive() { return 0; }
        sudo_session_start
        keeper="$_DF_SUDO_KEEPER_PID"
        sleeper=""
        for attempt in {1..100}; do
            sleeper="$(pgrep -P "$keeper" | head -1 || true)"
            [[ -n "$sleeper" ]] && break
            sleep 0.01
        done
        test -n "$sleeper"
        sudo_session_stop
        kill -0 "$keeper" 2>/dev/null && exit 97
        kill -0 "$sleeper" 2>/dev/null && exit 96
        test "$(grep -cx -- "-v" "$SUDO_LOG")" = 1
    '

    [ "$status" -eq 0 ]
}

@test "failed visible sudo authentication fails without starting a keeper" {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" REPO="$REPO" \
        SUDO_FAIL_FOREGROUND=1 bash -c '
            source "$REPO/install/_lib.sh"
            _sudo_session_interactive() { return 0; }
            if sudo_session_start; then exit 98; fi
            test -z "${_DF_SUDO_KEEPER_PID:-}"
        '

    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo authentication failed"* ]]
}

@test "renewal failure is visible and recorded as a degradation" {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" REPO="$REPO" \
        SUDO_ATTEMPTS="$BATS_TEST_TMPDIR/attempts" SUDO_FAIL_NONINTERACTIVE_AFTER=2 \
        DF_DEGRADE_LOG="$BATS_TEST_TMPDIR/degradations" bash -c '
            source "$REPO/install/_lib.sh"
            sleep() { return 0; }
            _DF_SUDO_SESSION_OWNER=$$
            if _sudo_session_keepalive; then exit 98; fi
            test "$(cat "$SUDO_ATTEMPTS")" = 2
            grep -Fq "sudo credential renewal failed" "$DF_DEGRADE_LOG"
        '

    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo credential renewal failed"* ]]
}

@test "keeper stops without renewal after its bootstrap owner is gone" {
    run_helper '
        source "$REPO/install/_lib.sh"
        _DF_SUDO_SESSION_OWNER=999999
        sleep() { return 0; }
        _sudo_session_keepalive
        test ! -e "$SUDO_LOG"
    '

    [ "$status" -eq 0 ]
}

run_bootstrap_exit_harness() {
    local action="$1" expected_status="$2"
    local summary_marker="$BATS_TEST_TMPDIR/exit-summary"
    local keeper_marker="$BATS_TEST_TMPDIR/exit-keeper"
    local tmp_marker="$BATS_TEST_TMPDIR/exit-tmp"
    local bootstrap_exit
    bootstrap_exit="$(sed -n '/^_bootstrap_exit() {/,/^}/p' "$REPO/bootstrap.sh")"

    run env PATH="$FAKE_BIN:/usr/bin:/bin" REPO="$REPO" \
        SUMMARY_MARKER="$summary_marker" KEEPER_MARKER="$keeper_marker" TMP_MARKER="$tmp_marker" \
        BOOTSTRAP_EXIT="$bootstrap_exit" ACTION="$action" bash -c '
            source "$REPO/install/_lib.sh"
            _bootstrap_summary() { printf "%s\\n" "$1" > "$SUMMARY_MARKER"; return "$1"; }
            _BOOTSTRAP_TMP="$(mktemp -d)"
            printf "%s\\n" "$_BOOTSTRAP_TMP" > "$TMP_MARKER"
            ( sleep 120 ) &
            _DF_SUDO_KEEPER_PID=$!
            printf "%s\\n" "$_DF_SUDO_KEEPER_PID" > "$KEEPER_MARKER"
            eval "$BOOTSTRAP_EXIT"
            trap "_bootstrap_exit" EXIT
            trap "exit 130" INT
            trap "exit 143" TERM
            case "$ACTION" in
                normal) exit 0 ;;
                error) exit 41 ;;
                int) kill -INT $$ ;;
                term) kill -TERM $$ ;;
            esac
        '

    [ "$status" -eq "$expected_status" ]
    [ "$(cat "$summary_marker")" = "$expected_status" ]
    local keeper
    keeper="$(cat "$keeper_marker")"
    ! kill -0 "$keeper" 2>/dev/null
    [ ! -d "$(cat "$tmp_marker")" ]
}

@test "bootstrap exit cleanup preserves normal and error statuses" {
    run_bootstrap_exit_harness normal 0
    run_bootstrap_exit_harness error 41
}

@test "bootstrap exit cleanup preserves INT and TERM statuses" {
    run_bootstrap_exit_harness int 130
    run_bootstrap_exit_harness term 143
}

@test "Linux never invokes sudo" {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" REPO="$REPO" \
        DF_FIXTURE_OS=Linux bash -c '
            source "$REPO/install/_lib.sh"
            sudo_session_start
            sudo_session_stop
            test ! -e "$SUDO_LOG"
        '

    [ "$status" -eq 0 ]
}

@test "DF_SUDO=0 opts out without touching sudo on macOS" {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" REPO="$REPO" \
        DF_SUDO=0 bash -c '
            source "$REPO/install/_lib.sh"
            sudo_session_start
            sudo_session_stop
            test ! -e "$SUDO_LOG"
        '

    [ "$status" -eq 0 ]
}

@test "DF_SUDO accepts only the documented values" {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" REPO="$REPO" \
        DF_SUDO=always bash -c 'source "$REPO/install/_lib.sh"'

    [ "$status" -ne 0 ]
    [[ "$output" == *"DF_SUDO must be 'auto' or '0'"* ]]
}

@test "unattended macOS only uses a non-prompting cached-ticket check" {
    run_helper '
        source "$REPO/install/_lib.sh"
        _sudo_session_interactive() { return 1; }
        sudo_session_start
        sudo_session_stop
        test "$(grep -cx -- "-v" "$SUDO_LOG" || true)" = 0
        test "$(grep -cx -- "-n -v" "$SUDO_LOG")" = 1
    '

    [ "$status" -eq 0 ]
}
