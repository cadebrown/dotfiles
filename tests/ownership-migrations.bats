#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export MIGRATION_HOME="$BATS_TEST_TMPDIR/home" MIGRATION_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$MIGRATION_HOME/npm/bin" "$MIGRATION_HOME/brew/bin" "$MIGRATION_BIN"
    export MIGRATION_LOG="$MIGRATION_HOME/calls"
    : > "$MIGRATION_LOG"
    for binary in "$MIGRATION_HOME/npm/bin/opencode" "$MIGRATION_HOME/brew/bin/opencode" "$MIGRATION_HOME/brew/bin/ollama"; do
        printf '#!/bin/sh\nprintf "1.0.0\\n"\n' > "$binary"
        chmod +x "$binary"
    done
    touch "$MIGRATION_HOME/old-opencode" "$MIGRATION_HOME/app-server"
    cat > "$MIGRATION_BIN/npm" <<'EOF'
#!/bin/sh
printf '%s\n' "$MIGRATION_HOME/npm"
EOF
    cat > "$MIGRATION_BIN/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$MIGRATION_LOG"
case "$*" in
    'list --formula opencode') test -f "$MIGRATION_HOME/old-opencode" ;;
    'list --formula ollama') exit 0 ;;
    'uses --installed opencode') printf '%s' "${MIGRATION_DEPENDENTS:-}" ;;
    '--prefix opencode'|'--prefix ollama') printf '%s\n' "$MIGRATION_HOME/brew" ;;
    'list --versions opencode') printf 'opencode 1.0.0\n' ;;
    'uninstall --formula opencode')
        test -x "$HOME"/.local/share/dotfiles/rollback/opencode-homebrew/*/opencode || exit 9
        rm "$MIGRATION_HOME/old-opencode" "$MIGRATION_HOME/brew/bin/opencode" ;;
    'services run ollama'|'services start ollama')
        test "${MIGRATION_START_FAIL:-0}" = 0 || exit 1
        touch "$MIGRATION_HOME/formula-server" ;;
    'services stop ollama') rm -f "$MIGRATION_HOME/formula-server" ;;
    *) exit 1 ;;
esac
EOF
    cat > "$MIGRATION_BIN/pgrep" <<'EOF'
#!/bin/sh
case "$*" in
    *Resources*) test ! -f "$MIGRATION_HOME/app-server" || printf '111\n' ;;
esac
EOF
    cat > "$MIGRATION_BIN/lsof" <<'EOF'
#!/bin/sh
case "$*" in
    *LISTEN*) printf '%s\n' "${MIGRATION_LISTENER:-111}" ;;
    *ESTABLISHED*)
        test "${MIGRATION_BUSY:-0}" = 0 || printf 'active connection\n'
        exit 1 ;;
esac
EOF
    cat > "$MIGRATION_BIN/curl" <<'EOF'
#!/bin/sh
case "$*" in
    */api/ps) printf '{"models":%s}\n' "${MIGRATION_LOADED:-[]}" ;;
    */api/tags) printf '{"models":[{"name":"saved-model","digest":"saved-digest"}]}\n' ;;
    *) exit 1 ;;
esac
EOF
    cat > "$MIGRATION_BIN/launchctl" <<'EOF'
#!/bin/sh
printf 'launchctl %s\n' "$*" >> "$MIGRATION_LOG"
case "$1" in
    print-disabled) printf '"other.service" => true\n' ;;
    print) exit 1 ;;
esac
EOF
    cat > "$MIGRATION_BIN/open" <<'EOF'
#!/bin/sh
printf 'open %s\n' "$*" >> "$MIGRATION_LOG"
touch "$MIGRATION_HOME/app-server"
EOF
    chmod +x "$MIGRATION_BIN/"*
}

@test "OpenCode ownership migration verifies npm and keeps rollback before retiring formula once" {
    mkdir -p "$MIGRATION_HOME/.config/opencode"
    printf 'user-owned config\n' > "$MIGRATION_HOME/.config/opencode/preserved"
    run env HOME="$MIGRATION_HOME" DF_USE_PLAT=0 PATH="$MIGRATION_BIN:$PATH" bash -c '
        source "$1/install/node.sh"
        run_logged() { "$@"; }
        _migrate_opencode_owner
        _migrate_opencode_owner
    ' _ "$REPO"
    [ "$status" -eq 0 ]
    [ ! -e "$MIGRATION_HOME/old-opencode" ]
    local saved=("$MIGRATION_HOME"/.local/share/dotfiles/rollback/opencode-homebrew/*/opencode)
    [ "${#saved[@]}" -eq 1 ]
    [ -x "${saved[0]}" ]
    [ "$(grep -c '^brew uninstall --formula opencode$' "$MIGRATION_LOG")" -eq 1 ]
    [ "$(cat "$MIGRATION_HOME/.config/opencode/preserved")" = 'user-owned config' ]
}

@test "OpenCode migration preserves formula when npm fails or a dependent remains" {
    printf '#!/bin/sh\nexit 17\n' > "$MIGRATION_HOME/npm/bin/opencode"
    run env HOME="$MIGRATION_HOME" DF_USE_PLAT=0 PATH="$MIGRATION_BIN:$PATH" bash -c \
        'source "$1/install/node.sh"; _migrate_opencode_owner' _ "$REPO"
    [ "$status" -ne 0 ]
    [ -x "$MIGRATION_HOME/brew/bin/opencode" ]
    printf '#!/bin/sh\nexit 0\n' > "$MIGRATION_HOME/npm/bin/opencode"
    run env HOME="$MIGRATION_HOME" DF_USE_PLAT=0 MIGRATION_DEPENDENTS=dependent PATH="$MIGRATION_BIN:$PATH" bash -c \
        'source "$1/install/node.sh"; _migrate_opencode_owner' _ "$REPO"
    [ "$status" -ne 0 ]
    [ -x "$MIGRATION_HOME/brew/bin/opencode" ]
    ! grep -q 'brew uninstall' "$MIGRATION_LOG"
}

@test "idle Ollama app migrates once with transient service and unchanged models" {
    run env HOME="$MIGRATION_HOME" DF_USE_PLAT=0 DF_START_LOCAL_SERVICES=0 PATH="$MIGRATION_BIN:$PATH" bash -c '
        source "$1/install/macos-services.sh"
        run_logged() { "$@"; }
        _stop_ollama_app_pid() {
            [[ "$1" == 111 && "$2" == "/Applications/Ollama.app/Contents/Resources/ollama serve" ]] || return 1
            rm "$MIGRATION_HOME/app-server"
        }
        _reconcile_ollama_owner
        _reconcile_ollama_owner
    ' _ "$REPO"
    [ "$status" -eq 0 ]
    [ -f "$MIGRATION_HOME/formula-server" ]
    [ ! -e "$MIGRATION_HOME/app-server" ]
    [ "$(grep -c '^brew services run ollama$' "$MIGRATION_LOG")" -eq 1 ]
    ! grep -q '^brew services start' "$MIGRATION_LOG"
    cmp "$MIGRATION_HOME"/.local/share/dotfiles/rollback/ollama-app/*/models-before.json \
        "$MIGRATION_HOME"/.local/share/dotfiles/rollback/ollama-app/*/models-after.json
}

@test "Ollama loaded models connections and unrelated listeners defer migration without changes" {
    local setting
    for setting in 'MIGRATION_LOADED=[{}]' MIGRATION_BUSY=1 MIGRATION_LISTENER=222; do
        run env HOME="$MIGRATION_HOME" DF_USE_PLAT=0 "$setting" PATH="$MIGRATION_BIN:$PATH" bash -c \
            'source "$1/install/macos-services.sh"; _reconcile_ollama_owner' _ "$REPO"
        [ "$status" -ne 0 ]
        [ -f "$MIGRATION_HOME/app-server" ]
    done
    ! grep -q '^launchctl disable\|^brew services' "$MIGRATION_LOG"
}

@test "failed Ollama formula startup restores the app backend and prior enablement" {
    run env HOME="$MIGRATION_HOME" DF_USE_PLAT=0 MIGRATION_START_FAIL=1 PATH="$MIGRATION_BIN:$PATH" bash -c '
        source "$1/install/macos-services.sh"
        run_logged() { "$@"; }
        _stop_ollama_app_pid() { rm "$MIGRATION_HOME/app-server"; }
        _reconcile_ollama_owner
    ' _ "$REPO"
    [ "$status" -ne 0 ]
    [ -f "$MIGRATION_HOME/app-server" ]
    grep -q '^launchctl enable .*com.ollama.ollama' "$MIGRATION_LOG"
    grep -q '^open -g -a /Applications/Ollama.app$' "$MIGRATION_LOG"
}
