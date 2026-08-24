#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_HOME" "$FAKE_BIN" "$BATS_TEST_TMPDIR/unrelated"

    cat > "$FAKE_BIN/curl" <<'SH'
#!/bin/sh
out=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
case "$url" in
    */install/_lib.sh) cp "$REPO_SOURCE/install/_lib.sh" "$out" ;;
    *) printf 'unexpected curl URL: %s\n' "$url" >&2; exit 1 ;;
esac
SH

    cat > "$FAKE_BIN/git" <<'SH'
#!/bin/sh
if [ "$1" = clone ]; then
    cp -R "$REPO_SOURCE" "$3"
    exit 0
fi
exec /usr/bin/git "$@"
SH

    chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/git"
}

make_fake_chezmoi() {
    local use_plat="$1" local_plat
    local_plat="$(env HOME="$TEST_HOME" DF_USE_PLAT="$use_plat" PATH="/usr/bin:/bin" \
        bash -c 'source "$1/install/_lib.sh"; printf %s "$LOCAL_PLAT"' _ "$REPO")"
    mkdir -p "$local_plat/bin"
    cat > "$local_plat/bin/chezmoi" <<'SH'
#!/bin/sh
case "${1:-}" in
    --version) printf 'chezmoi version test\n' ;;
    init) exit 0 ;;
    source-path) printf '%s/dotfiles/home\n' "$HOME" ;;
esac
SH
    chmod +x "$local_plat/bin/chezmoi"
}

run_remote_bootstrap() {
    local use_plat="$1"
    make_fake_chezmoi "$use_plat"

    run bash -c '
        cd "$1"
        env \
            HOME="$2" PATH="$3:/usr/bin:/bin" REPO_SOURCE="$4" \
            DF_USE_PLAT="$5" DF_NAME=Test DF_EMAIL=test@example.com \
            DF_DO_SCRATCH=0 DF_DO_DIRS=0 DF_DO_ZSH=0 DF_DO_PACKAGES=0 \
            DF_DO_QUARTO=0 DF_DO_MACOS_SERVICES=0 DF_DO_MACOS_SETTINGS=0 \
            DF_DO_MACOS_QUICK_ACTIONS=0 DF_DO_PYTHON=0 DF_DO_NODE=0 \
            DF_DO_RUST=0 DF_DO_GO=0 DF_DO_JULIA=0 DF_DO_LEAN=0 \
            DF_DO_LATEX=0 DF_DO_CLAUDE=0 DF_DO_CODEX=0 \
            DF_DO_CLAUDE_DESKTOP=0 DF_DO_CODEX_DESKTOP=0 DF_DO_LINEARMOUSE=0 \
            DF_DO_CURSOR=0 DF_DO_VSCODE=0 DF_DO_CMAKE=0 DF_DO_LOCAL_LLM=0 \
            DF_DO_MEMORY=0 DF_DO_SKILLS=0 DF_DO_BLENDER_MCP=0 \
            DF_DO_AUTH=0 DF_DO_OVERLAYS=0 \
            bash < "$4/bootstrap.sh"
    ' _ "$BATS_TEST_TMPDIR/unrelated" "$TEST_HOME" "$FAKE_BIN" "$REPO" "$use_plat"
}

@test "piped bootstrap clones to HOME/dotfiles from an unrelated directory" {
    run_remote_bootstrap 0

    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/dotfiles/bootstrap.sh" ]
    [[ "$output" == *"Cloning cadebrown/dotfiles → $TEST_HOME/dotfiles"* ]]
    [[ "$output" != *"→ $BATS_TEST_TMPDIR/unrelated"* ]]
}

@test "piped bootstrap defers PLAT validation until the repository exists" {
    run_remote_bootstrap 1

    [ "$status" -eq 0 ]
    [[ "$output" == *"DF_USE_PLAT=1"* ]]
    [[ "$output" == *"LOCAL_PLAT=$TEST_HOME/.local/plat_"* ]]
}
