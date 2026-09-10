#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    HOME_DIR="$BATS_TEST_TMPDIR/home"
    TEST_REPO="$BATS_TEST_TMPDIR/repo"
    BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$HOME_DIR/.config/dotfiles/hosts" "$TEST_REPO" "$BIN"
    for directory in install home packages; do ln -s "$REPO/$directory" "$TEST_REPO/$directory"; done
    mkdir -p "$TEST_REPO/dotfiles-team/hosts"
    cat > "$BIN/hostname" <<'SH'
#!/bin/sh
printf '%s\n' fixture-host.example
SH
    chmod +x "$BIN/hostname"
}

resolve() {
    env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" "$@" /bin/bash -c '
        source "$1/install/_lib.sh"
        printf "%s|%s|%s|%s|%s|%s\n" "$DF_PROFILE" "$DF_USE_PLAT" "$DF_PLAT" "$DF_TOOLS_ROOT" "${DF_STATE_ROOT:-}" "${DF_DO_NODE:-}"
    ' _ "$TEST_REPO"
}

@test "host configuration precedence is invocation, local, overlay, then defaults" {
    cat > "$TEST_REPO/dotfiles-team/hosts/fixture-host.example.env" <<'EOF'
DF_PROFILE=core
DF_USE_PLAT=1
DF_PLAT=auto
DF_TOOLS_ROOT=/overlay tools
DF_STATE_ROOT=/overlay-state
DF_DO_NODE=0
EOF
    cat > "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env" <<'EOF'
DF_PROFILE=full
DF_TOOLS_ROOT=/local tools
DF_DO_NODE=1
EOF
    run resolve
    [ "$status" -eq 0 ]
    [ "$output" = 'full|1|auto|/local tools|/overlay-state|1' ]

    run resolve DF_PROFILE=core DF_USE_PLAT=0 DF_TOOLS_ROOT=/invocation DF_DO_NODE=0
    [ "$status" -eq 0 ]
    [ "$output" = 'core|0|auto|/invocation|/overlay-state|0' ]
}

@test "resolver bookkeeping stays process-local so child invocation overrides work" {
    cat > "$TEST_REPO/dotfiles-team/hosts/fixture-host.example.env" <<'EOF'
DF_PROFILE=full
DF_STATE_ROOT=/overlay-state
EOF
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" /bin/bash -c '
        source "$1/install/_host-config.sh"; _host_config_resolve "$1"
        env DF_PROFILE=core DF_STATE_ROOT=/invocation-state /bin/bash -c "source \"$1/install/_host-config.sh\"; _host_config_resolve \"$1\"; printf \"%s|%s|%s\\n\" \"\$DF_PROFILE\" \"\$DF_STATE_ROOT\" \"\$CODEX_HOME\"" _ "$1"
    ' _ "$TEST_REPO"
    [ "$status" -eq 0 ]
    # CODEX_HOME inherited by a subprocess is still an explicit environment
    # setting and therefore remains untouched while DF_STATE_ROOT overrides.
    [ "$output" = 'core|/invocation-state|/overlay-state/codex' ]
}

@test "host files are hostname-separated data and reject shell syntax or unknown keys" {
    printf 'DF_PROFILE=core\n' > "$HOME_DIR/.config/dotfiles/hosts/other-host.env"
    run resolve
    [ "$status" -eq 0 ]
    [[ "$output" == full'|0|auto|'* ]]

    printf 'DF_PROFILE=$(false)\n' > "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env"
    run resolve
    [ "$status" -ne 0 ]
    [[ "$output" == *'contains shell syntax'* ]]

    printf 'DF_STATE_ROOT=/tmp/$(touch should-not-run)\n' > "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env"
    run resolve
    [ "$status" -ne 0 ]
    [[ "$output" == *'contains shell syntax'* ]]
    [ ! -e "$HOME_DIR/should-not-run" ]

    printf 'NOT_A_DF_KEY=value\n' > "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env"
    run resolve
    [ "$status" -ne 0 ]
    [[ "$output" == *'unknown key'* ]]
}

@test "explicit tools root is not redirected through a shared-home symlink" {
    mkdir -p "$HOME_DIR/physical local"
    ln -s "$HOME_DIR/physical local" "$HOME_DIR/.local"
    cat > "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env" <<EOF
DF_TOOLS_ROOT=$HOME_DIR/host tools
DF_USE_PLAT=0
EOF
    run resolve
    [ "$status" -eq 0 ]
    [[ "$output" == *"|$HOME_DIR/host tools||"* ]]
}

@test "resolver has Bash and Zsh parity when Zsh is installed" {
    command -v zsh >/dev/null 2>&1 || skip 'zsh is not installed'
    cat > "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env" <<'EOF'
DF_PROFILE=core
DF_USE_PLAT=0
DF_TOOLS_ROOT=/host tools
DF_STATE_ROOT=/host state
EOF
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" /bin/bash -c '
        source "$1/install/_host-config.sh"; _host_config_resolve "$1"; printf "%s|%s|%s|%s\n" "$DF_PROFILE" "$DF_USE_PLAT" "$DF_TOOLS_ROOT" "$DF_STATE_ROOT"
    ' _ "$TEST_REPO"
    [ "$status" -eq 0 ]
    bash_result="$output"
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" zsh -c '
        source "$1/install/_host-config.sh"; _host_config_resolve "$1"; print -r -- "$DF_PROFILE|$DF_USE_PLAT|$DF_TOOLS_ROOT|$DF_STATE_ROOT"
    ' _ "$TEST_REPO"
    [ "$status" -eq 0 ]
    [ "$output" = "$bash_result" ]
}

@test "resolver defaults with no overlays and preserves Zsh NOMATCH" {
    command -v zsh >/dev/null 2>&1 || skip 'zsh is not installed'
    no_overlay_root="$BATS_TEST_TMPDIR/no-overlay"
    mkdir -p "$no_overlay_root"
    ln -s "$REPO/install" "$no_overlay_root/install"
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" bash -c '
        source "$1/install/_host-config.sh"; _host_config_resolve "$1"; printf "%s|%s|%s\n" "$DF_PROFILE" "$DF_USE_PLAT" "$DF_TOOLS_ROOT"
    ' _ "$no_overlay_root"
    [ "$status" -eq 0 ]
    [ "$output" = "full|0|$HOME_DIR/.local" ]
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" zsh -c '
        [[ -o nomatch ]] || exit 2
        source "$1/install/_host-config.sh"; _host_config_resolve "$1"
        [[ -o nomatch ]] || exit 3
        print -r -- "$DF_PROFILE|$DF_USE_PLAT|$DF_TOOLS_ROOT"
    ' _ "$no_overlay_root"
    [ "$status" -eq 0 ]
    [ "$output" = "full|0|$HOME_DIR/.local" ]
}

@test "host configure refuses a headless write" {
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" bash "$REPO/install/host.sh" configure
    [ "$status" -eq 2 ]
    [[ "$output" == *'requires an interactive terminal'* ]]
    [ ! -e "$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env" ]
}

@test "host configure writes default policy atomically through a PTY" {
    command -v script >/dev/null 2>&1 || skip 'script is not installed'
    if script --version >/dev/null 2>&1; then
        run bash -c 'printf "\n\n\n\n\n" | script -q -c "env HOME=$1 PATH=$2:/usr/bin:/bin /bin/bash $3/install/host.sh configure" /dev/null' \
            _ "$HOME_DIR" "$BIN" "$REPO"
    else
        run bash -c 'printf "\n\n\n\n\n" | env HOME="$1" PATH="$2:/usr/bin:/bin" script -q /dev/null /bin/bash "$3/install/host.sh" configure' \
            _ "$HOME_DIR" "$BIN" "$REPO"
    fi
    [ "$status" -eq 0 ]
    host_file="$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env"
    [ -f "$host_file" ]
    mode="$(stat -c '%a' "$host_file" 2>/dev/null || stat -f '%Lp' "$host_file")"
    [ "$mode" = 600 ]
    run env HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" bash "$REPO/install/host.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *'local_config=1'* ]]
    [[ "$output" == *"DF_TOOLS_ROOT=$HOME_DIR/.local"* ]]
    [[ "$output" == *'DF_STATE_ROOT='* ]]
}

@test "host configure writes explicit empty roots to clear overlay presets" {
    command -v script >/dev/null 2>&1 || skip 'script is not installed'
    cat > "$TEST_REPO/dotfiles-team/hosts/fixture-host.example.env" <<'EOF'
DF_TOOLS_ROOT=/overlay-tools
DF_STATE_ROOT=/overlay-state
EOF
    if script --version >/dev/null 2>&1; then
        run bash -c '{ for answer in full 0 auto - -; do printf "%s\n" "$answer"; sleep 0.1; done; } | script -q -c "env HOME=$1 PATH=$2:/usr/bin:/bin DF_ROOT=$3 /bin/bash $4/install/host.sh configure" /dev/null' \
            _ "$HOME_DIR" "$BIN" "$TEST_REPO" "$REPO"
    else
        run bash -c '{ for answer in full 0 auto - -; do printf "%s\n" "$answer"; sleep 0.1; done; } | env HOME="$1" PATH="$2:/usr/bin:/bin" DF_ROOT="$3" script -q /dev/null /bin/bash "$4/install/host.sh" configure' \
            _ "$HOME_DIR" "$BIN" "$TEST_REPO" "$REPO"
    fi
    [ "$status" -eq 0 ]
    host_file="$HOME_DIR/.config/dotfiles/hosts/fixture-host.example.env"
    grep -Fxq 'DF_TOOLS_ROOT=' "$host_file"
    grep -Fxq 'DF_STATE_ROOT=' "$host_file"
    run env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin" DF_ROOT="$TEST_REPO" bash "$REPO/install/host.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"DF_TOOLS_ROOT=$HOME_DIR/.local"* ]]
    [[ "$output" == *'DF_STATE_ROOT='* ]]
    [[ "$output" == *'CODEX_HOME='* ]]
}
