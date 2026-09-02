#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "editor installers reject a missing selected desktop CLI" {
    local installer command gate
    for row in "cursor.sh cursor DF_DO_CURSOR" "vscode.sh code DF_DO_VSCODE"; do
        read -r installer command gate <<< "$row"
        run env HOME="$BATS_TEST_TMPDIR/home-$command" DF_USE_PLAT=0 \
            PATH=/usr/bin:/bin /bin/bash "$REPO/install/$installer"

        [ "$status" -ne 0 ]
        [[ "$output" == *"$command CLI not found"* ]]
        [[ "$output" == *"$gate=0"* ]]
    done
}

@test "editor installers verify extension state instead of trusting exit zero" {
    local installer command source_dir fake_home fake_bin
    for row in "cursor.sh cursor cursor" "vscode.sh code vscode"; do
        read -r installer command source_dir <<< "$row"
        fake_home="$BATS_TEST_TMPDIR/home-$command"
        fake_bin="$BATS_TEST_TMPDIR/bin-$command"
        mkdir -p "$fake_home/.config/$source_dir" "$fake_bin"
        cp "$REPO/home/dot_config/$source_dir/settings.json" \
            "$fake_home/.config/$source_dir/"
        if [[ -f "$REPO/home/dot_config/$source_dir/keybindings.json" ]]; then
            cp "$REPO/home/dot_config/$source_dir/keybindings.json" \
                "$fake_home/.config/$source_dir/"
        fi

        printf '%s\n' \
            '#!/bin/sh' \
            'case "$1" in' \
            '  --list-extensions) exit 0 ;;' \
            '  --install-extension|--update-extensions) exit 0 ;;' \
            'esac' \
            'exit 0' > "$fake_bin/$command"
        chmod +x "$fake_bin/$command"

        run env HOME="$fake_home" DF_USE_PLAT=0 \
            PATH="$fake_bin:$PATH" /bin/bash "$REPO/install/$installer"

        [ "$status" -ne 0 ]
        [[ "$output" == *"missing"*"declared extension(s) after installation"* ]]
    done
}

@test "macOS LLDB installer deploys both commands into ARCH_BIN" {
    local fake_home="$BATS_TEST_TMPDIR/lldb-home"
    local fake_bin="$BATS_TEST_TMPDIR/lldb-bin"
    local lldb_prefix="$BATS_TEST_TMPDIR/lldb-prefix"
    mkdir -p "$fake_home" "$fake_bin" "$lldb_prefix/bin"

    cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Darwin\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Darwin\n' ;;
esac
EOF
    cat > "$fake_bin/brew" <<EOF
#!/bin/sh
if [ "\${1:-}" = list ] && [ "\${2:-}" = lldb ]; then exit 0; fi
if [ "\${1:-}" = --prefix ] && [ "\${2:-}" = lldb ]; then
    printf '%s\n' '$lldb_prefix'
    exit 0
fi
exit 1
EOF
    cat > "$lldb_prefix/bin/lldb" <<'EOF'
#!/bin/sh
case "$*" in
    *"target create /bin/sh"*) exit 0 ;;
esac
exit 1
EOF
    cat > "$lldb_prefix/bin/lldb-dap" <<'EOF'
#!/bin/sh
test "${1:-}" = --help
EOF
    chmod +x "$lldb_prefix/bin/lldb" "$lldb_prefix/bin/lldb-dap"
    chmod +x "$fake_bin/uname" "$fake_bin/brew"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fake_bin:/usr/bin:/bin" \
        /bin/bash "$REPO/install/lldb.sh"

    [ "$status" -eq 0 ]
    [ "$(readlink "$fake_home/.local/bin/lldb")" = "$lldb_prefix/bin/lldb" ]
    [ "$(readlink "$fake_home/.local/bin/lldb-dap")" = "$lldb_prefix/bin/lldb-dap" ]
}

@test "Homebrew LLDB installer repairs an installed binary that fails at runtime" {
    local fake_home="$BATS_TEST_TMPDIR/lldb-repair-home"
    local fake_bin="$BATS_TEST_TMPDIR/lldb-repair-bin"
    local lldb_prefix="$BATS_TEST_TMPDIR/lldb-repair-prefix"
    mkdir -p "$fake_home" "$fake_bin" "$lldb_prefix/bin"

    cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Darwin\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Darwin\n' ;;
esac
EOF
    cat > "$fake_bin/brew" <<EOF
#!/bin/sh
if [ "\${1:-}" = list ] && [ "\${2:-}" = lldb ]; then exit 0; fi
if [ "\${1:-}" = --prefix ] && [ "\${2:-}" = lldb ]; then
    printf '%s\n' '$lldb_prefix'
    exit 0
fi
if [ "\${1:-}" = reinstall ] && [ "\${2:-}" = lldb ]; then
    touch '$lldb_prefix/healthy'
    exit 0
fi
exit 1
EOF
    for command in lldb lldb-dap; do
        cat > "$lldb_prefix/bin/$command" <<EOF
#!/bin/sh
test -f '$lldb_prefix/healthy'
EOF
        chmod +x "$lldb_prefix/bin/$command"
    done
    chmod +x "$fake_bin/uname" "$fake_bin/brew"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fake_bin:/usr/bin:/bin" \
        /bin/bash "$REPO/install/lldb.sh"

    [ "$status" -eq 0 ]
    [ -f "$lldb_prefix/healthy" ]
}

@test "Linux LLDB wrappers replace symlinks without overwriting their targets" {
    local fake_home="$BATS_TEST_TMPDIR/lldb-linux-home"
    local fake_bin="$BATS_TEST_TMPDIR/lldb-linux-bin"
    local victim="$BATS_TEST_TMPDIR/lldb-victim"
    mkdir -p "$fake_home/.local/bin" "$fake_bin"
    printf 'original\n' > "$victim"
    ln -s "$victim" "$fake_home/.local/bin/lldb"
    ln -s "$victim" "$fake_home/.local/bin/lldb-dap"

    cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Linux\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Linux\n' ;;
esac
EOF
    cat > "$fake_bin/apt-cache" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == show && "$2" == *-23 ]] && exit 1
[[ "$1" == show ]] && exit 0
exit 1
EOF
    cat > "$fake_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        Dir::Cache::archives=*) archives="${arg#*=}" ;;
    esac
done
mkdir -p "$archives"
touch "$archives/package.deb"
EOF
    cat > "$fake_bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -x ]] || exit 1
dest="$3"
mkdir -p "$dest/usr/lib/llvm-22/bin"
for command in lldb lldb-dap; do
    printf '#!/bin/sh\nexit 0\n' > "$dest/usr/lib/llvm-22/bin/$command"
    chmod +x "$dest/usr/lib/llvm-22/bin/$command"
done
EOF
    chmod +x "$fake_bin/uname" "$fake_bin/apt-cache" "$fake_bin/apt-get" "$fake_bin/dpkg-deb"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fake_bin:/usr/bin:/bin" \
        /bin/bash "$REPO/install/lldb.sh"

    [ "$status" -eq 0 ]
    [ "$(cat "$victim")" = original ]
    [ ! -L "$fake_home/.local/bin/lldb" ]
    [ ! -L "$fake_home/.local/bin/lldb-dap" ]
}

@test "Linux LLDB forces package downloads when apt reports them installed" {
    local fake_home="$BATS_TEST_TMPDIR/lldb-installed-home"
    local fake_bin="$BATS_TEST_TMPDIR/lldb-installed-bin"
    mkdir -p "$fake_home/.local/bin" "$fake_bin"

    cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Linux\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Linux\n' ;;
esac
EOF
    cat > "$fake_bin/apt-cache" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == show && "$2" == *-23 ]] && exit 1
[[ "$1" == show ]] && exit 0
exit 1
EOF
    cat > "$fake_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
archives=""
reinstall=0
for arg in "$@"; do
    case "$arg" in
        --reinstall) reinstall=1 ;;
        Dir::Cache::archives=*) archives="${arg#*=}" ;;
    esac
done
[[ "$reinstall" == 1 ]] || exit 0
mkdir -p "$archives"
touch "$archives/package.deb"
EOF
    cat > "$fake_bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
dest="$3"
mkdir -p "$dest/usr/lib/llvm-22/bin"
for command in lldb lldb-dap; do
    printf '#!/bin/sh\nexit 0\n' > "$dest/usr/lib/llvm-22/bin/$command"
    chmod +x "$dest/usr/lib/llvm-22/bin/$command"
done
EOF
    chmod +x "$fake_bin/uname" "$fake_bin/apt-cache" "$fake_bin/apt-get" "$fake_bin/dpkg-deb"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fake_bin:/usr/bin:/bin" \
        /bin/bash "$REPO/install/lldb.sh"

    [ "$status" -eq 0 ]
    [ -x "$fake_home/.local/bin/lldb" ]
    [ -x "$fake_home/.local/bin/lldb-dap" ]
}

@test "Linux LLDB restores the previous tree when wrapper deployment fails" {
    local fake_home="$BATS_TEST_TMPDIR/lldb-rollback-home"
    local fake_bin="$BATS_TEST_TMPDIR/lldb-rollback-bin"
    local old_root="$fake_home/.local/lldb-22"
    mkdir -p "$fake_home/.local/bin" "$old_root/usr/lib/llvm-22/bin" "$fake_bin"
    printf 'previous-install\n' > "$old_root/receipt"
    printf '#!/bin/sh\nexit 1\n' > "$old_root/usr/lib/llvm-22/bin/lldb"
    cp "$old_root/usr/lib/llvm-22/bin/lldb" "$old_root/usr/lib/llvm-22/bin/lldb-dap"
    chmod +x "$old_root/usr/lib/llvm-22/bin/lldb" "$old_root/usr/lib/llvm-22/bin/lldb-dap"

    cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Linux\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Linux\n' ;;
esac
EOF
    cat > "$fake_bin/apt-cache" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == show && "$2" == *-23 ]] && exit 1
[[ "$1" == show ]] && exit 0
exit 1
EOF
    cat > "$fake_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        Dir::Cache::archives=*) archives="${arg#*=}" ;;
    esac
done
mkdir -p "$archives"
touch "$archives/package.deb"
EOF
    cat > "$fake_bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
dest="$3"
mkdir -p "$dest/usr/lib/llvm-22/bin"
for command in lldb lldb-dap; do
    printf '#!/bin/sh\nexit 0\n' > "$dest/usr/lib/llvm-22/bin/$command"
    chmod +x "$dest/usr/lib/llvm-22/bin/$command"
done
EOF
    chmod +x "$fake_bin/uname" "$fake_bin/apt-cache" "$fake_bin/apt-get" "$fake_bin/dpkg-deb"
    chmod 555 "$fake_home/.local/bin"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fake_bin:/usr/bin:/bin" \
        /bin/bash "$REPO/install/lldb.sh"

    chmod 755 "$fake_home/.local/bin"
    [ "$status" -ne 0 ]
    [ "$(cat "$old_root/receipt")" = previous-install ]
    [ ! -e "$old_root.previous" ]
}

@test "Linux LLDB removes a failed new major and restores prior wrappers" {
    local fake_home="$BATS_TEST_TMPDIR/lldb-cross-major-home"
    local fake_bin="$BATS_TEST_TMPDIR/lldb-cross-major-bin"
    local old_root="$fake_home/.local/lldb-21"
    mkdir -p "$fake_home/.local/bin" "$old_root" "$fake_bin"
    printf 'previous-major\n' > "$old_root/receipt"
    for command in lldb lldb-dap; do
        printf '#!/bin/sh\nprintf "old-%s\\n"\n' "$command" \
            > "$fake_home/.local/bin/$command"
        chmod +x "$fake_home/.local/bin/$command"
    done

    cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Linux\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Linux\n' ;;
esac
EOF
    cat > "$fake_bin/apt-cache" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == show && "$2" == *-23 ]] && exit 1
[[ "$1" == show && "$2" == *-22 ]] && exit 0
exit 1
EOF
    cat > "$fake_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        Dir::Cache::archives=*) archives="${arg#*=}" ;;
    esac
done
mkdir -p "$archives"
touch "$archives/package.deb"
EOF
    cat > "$fake_bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
dest="$3"
mkdir -p "$dest/usr/lib/llvm-22/bin"
for command in lldb lldb-dap; do
    printf '#!/bin/sh\nexit 1\n' > "$dest/usr/lib/llvm-22/bin/$command"
    chmod +x "$dest/usr/lib/llvm-22/bin/$command"
done
EOF
    chmod +x "$fake_bin/uname" "$fake_bin/apt-cache" "$fake_bin/apt-get" "$fake_bin/dpkg-deb"

    run env HOME="$fake_home" DF_USE_PLAT=0 PATH="$fake_bin:/usr/bin:/bin" \
        /bin/bash "$REPO/install/lldb.sh"

    [ "$status" -ne 0 ]
    [ ! -e "$fake_home/.local/lldb-22" ]
    [ "$(cat "$old_root/receipt")" = previous-major ]
    [ "$($fake_home/.local/bin/lldb)" = old-lldb ]
    [ "$($fake_home/.local/bin/lldb-dap)" = old-lldb-dap ]
}

@test "generic CLI startup validation rejects nonzero startup and loader failures" {
    local fake_home="$BATS_TEST_TMPDIR/entrypoint-home"
    mkdir -p "$fake_home/bin"
    printf '#!/bin/sh\nexit 1\n' > "$fake_home/bin/usage-error"
    printf '#!/bin/sh\nexit 127\n' > "$fake_home/bin/loader-error"
    chmod +x "$fake_home/bin/usage-error" "$fake_home/bin/loader-error"

    run env HOME="$fake_home" DF_USE_PLAT=0 DF_TOOL_SMOKE_TIMEOUT=0.2 \
        LC_ALL=C LANG=C bash -c '
        source "$1/install/_lib.sh"
        ! tool_entrypoint_healthy "$HOME/bin/usage-error"
        ! tool_entrypoint_healthy "$HOME/bin/loader-error"
    ' _ "$REPO"

    [ "$status" -eq 0 ]
}
