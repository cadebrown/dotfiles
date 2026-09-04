#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
    BREW_PREFIX="$BATS_TEST_TMPDIR/brew"
    mkdir -p "$TEST_HOME/.colima/default" "$TEST_HOME/.colima/work" \
        "$TEST_HOME/.colima/already-disabled" "$TEST_BIN" "$BREW_PREFIX"
    : > "$COMMAND_LOG"

    cat > "$TEST_HOME/.colima/default/colima.yaml" <<'EOF'
# default profile
runtime: docker
sshConfig: true
mounts:
  - location: ~/src
EOF
    chmod 0600 "$TEST_HOME/.colima/default/colima.yaml"
    cat > "$TEST_HOME/.colima/work/colima.yaml" <<'EOF'
runtime: docker
mounts: []
EOF
    cat > "$TEST_HOME/.colima/already-disabled/colima.yaml" <<'EOF'
runtime: docker
sshConfig: false
EOF

    cat > "$TEST_BIN/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Darwin\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Darwin\n' ;;
esac
EOF
    cat > "$TEST_BIN/colima" <<'EOF'
#!/bin/sh
printf 'colima %s\n' "$*" >> "$COMMAND_LOG"
case "$*" in
    'template --print')
        printf '%s\n' "$HOME/.colima/_templates/default.yaml"
        ;;
    'template --editor /usr/bin/true')
        mkdir -p "$HOME/.colima/_templates"
        cat > "$HOME/.colima/_templates/default.yaml" <<'TEMPLATE'
cpu: 2
memory: 2
runtime: docker
sshConfig: true
TEMPLATE
        ;;
    *) exit 1 ;;
esac
EOF
    cat > "$TEST_BIN/brew" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --prefix ]; then
    printf '%s\n' "$BREW_PREFIX"
    exit 0
fi
exit 1
EOF
    cat > "$TEST_BIN/launchctl" <<'EOF'
#!/bin/sh
[ "${1:-}" = disable ]
EOF
    chmod +x "$TEST_BIN/uname" "$TEST_BIN/colima" "$TEST_BIN/brew" \
        "$TEST_BIN/launchctl"
    export COMMAND_LOG BREW_PREFIX
}

file_mtime() {
    if [[ "$(uname -s)" == Darwin ]]; then
        stat -f %m "$1"
    else
        stat -c %Y "$1"
    fi
}

file_mode() {
    if [[ "$(uname -s)" == Darwin ]]; then
        stat -f %Lp "$1"
    else
        stat -c %a "$1"
    fi
}

@test "macOS services disable Colima SSH injection without starting it" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 DF_START_LOCAL_SERVICES=0 \
        PATH="$TEST_BIN:/usr/bin:/bin" /bin/bash "$REPO/install/macos-services.sh"
    [ "$status" -eq 0 ]

    for config in "$TEST_HOME/.colima/_templates/default.yaml" \
        "$TEST_HOME/.colima/default/colima.yaml" \
        "$TEST_HOME/.colima/work/colima.yaml" \
        "$TEST_HOME/.colima/already-disabled/colima.yaml"; do
        [ "$(grep -c '^sshConfig: false$' "$config")" -eq 1 ]
        ! grep -q '^sshConfig: true$' "$config"
    done
    [ "$(file_mode "$TEST_HOME/.colima/default/colima.yaml")" = 600 ]
    grep -q '^  - location: ~/src$' "$TEST_HOME/.colima/default/colima.yaml"
    run grep -Eq '^colima (start|stop)( |$)' "$COMMAND_LOG"
    [ "$status" -ne 0 ]

    touch -t 200001010000 "$TEST_HOME"/.colima/{_templates/default,default/colima,work/colima,already-disabled/colima}.yaml
    local mtimes_before=""
    for config in "$TEST_HOME/.colima/_templates/default.yaml" \
        "$TEST_HOME/.colima/default/colima.yaml" \
        "$TEST_HOME/.colima/work/colima.yaml" \
        "$TEST_HOME/.colima/already-disabled/colima.yaml"; do
        mtimes_before+="$(file_mtime "$config") "
    done
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 DF_START_LOCAL_SERVICES=0 \
        PATH="$TEST_BIN:/usr/bin:/bin" /bin/bash "$REPO/install/macos-services.sh"
    [ "$status" -eq 0 ]

    local mtimes_after=""
    for config in "$TEST_HOME/.colima/_templates/default.yaml" \
        "$TEST_HOME/.colima/default/colima.yaml" \
        "$TEST_HOME/.colima/work/colima.yaml" \
        "$TEST_HOME/.colima/already-disabled/colima.yaml"; do
        mtimes_after+="$(file_mtime "$config") "
    done
    [ "$mtimes_after" = "$mtimes_before" ]
    run grep -Eq '^colima (start|stop)( |$)' "$COMMAND_LOG"
    [ "$status" -ne 0 ]
}

@test "macOS services reject a symlinked Colima profile config" {
    local target="$BATS_TEST_TMPDIR/linked-colima.yaml"
    mkdir -p "$TEST_HOME/.colima/linked"
    printf 'runtime: docker\nsshConfig: true\n' > "$target"
    ln -s "$target" "$TEST_HOME/.colima/linked/colima.yaml"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 DF_START_LOCAL_SERVICES=0 \
        PATH="$TEST_BIN:/usr/bin:/bin" /bin/bash "$REPO/install/macos-services.sh"
    [ "$status" -ne 0 ]
    [ -L "$TEST_HOME/.colima/linked/colima.yaml" ]
    grep -q '^sshConfig: true$' "$target"
}

@test "SSH template has no Colima include" {
    run grep -q '\.colima/.*ssh_config' "$REPO/home/dot_ssh/config.tmpl"
    [ "$status" -ne 0 ]
    grep -q '^Include ~/.ssh/config.d/\*$' "$REPO/home/dot_ssh/config.tmpl"
}
