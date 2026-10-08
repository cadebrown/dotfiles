#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_TOOLS="$TEST_HOME/.local"
    FIXTURE_BIN="$BATS_TEST_TMPDIR/bin"
    export TEX_LOG="$BATS_TEST_TMPDIR/tex.log"
    export TEX_UPDATED="$BATS_TEST_TMPDIR/updated"
    export TEX_ARCH_BIN="$TEST_TOOLS/bin"
    export TEX_TLMGR_TEMPLATE="$BATS_TEST_TMPDIR/tlmgr"
    export TEX_INSTALLER_TEMPLATE="$BATS_TEST_TMPDIR/install-tinytex.sh"
    mkdir -p "$TEST_HOME" "$FIXTURE_BIN"

    cat >"$FIXTURE_BIN/uname" <<'SH'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = -s ]; then
    printf '%s\n' Linux
else
    exec /usr/bin/uname "$@"
fi
SH
    cat >"$FIXTURE_BIN/curl" <<'SH'
#!/usr/bin/env bash
printf 'download\n' >>"$TEX_LOG"
while (( $# )); do
    if [[ "$1" == -o ]]; then
        cp "$TEX_INSTALLER_TEMPLATE" "$2"
        exit 0
    fi
    shift
done
exit 2
SH
    cat >"$TEX_INSTALLER_TEMPLATE" <<'SH'
#!/bin/sh
printf 'installer <%s> <%s>\n' "$1" "$2" >>"$TEX_LOG"
[ "$1" = '' ] && [ "$2" = --no-path ] || exit 2
[ "${TEX_FAIL_INSTALLER:-0}" = 0 ] || exit 11
[ "${TEX_SKIP_TLMGR:-0}" = 0 ] || exit 0
mkdir -p "$TINYTEX_DIR/.TinyTeX/bin/fixture-linux"
cp "$TEX_TLMGR_TEMPLATE" "$TINYTEX_DIR/.TinyTeX/bin/fixture-linux/tlmgr"
SH
    cat >"$TEX_TLMGR_TEMPLATE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEX_LOG"
case "$*" in
    'update --self'|'update --self --all')
        [[ "${TEX_FAIL_UPDATE:-0}" == 0 ]] || exit 12
        touch "$TEX_UPDATED"
        ;;
    'option sys_bin '*)
        [[ "$3" == "$TEX_ARCH_BIN" ]] || exit 13
        ;;
    'path add') mkdir -p "$TEX_ARCH_BIN" ;;
    'install latexmk chktex texcount latexdiff')
        [[ -f "$TEX_UPDATED" ]] || { printf 'tlmgr itself needs to be updated\n' >&2; exit 14; }
        [[ "${TEX_FAIL_BASELINE:-0}" == 0 ]] || exit 15
        for tex_command in pdflatex latexmk chktex texcount latexdiff; do
            [[ "$tex_command" != "${TEX_MISSING_COMMAND:-}" ]] || continue
            [[ -x "$TEX_ARCH_BIN/$tex_command" ]] && continue
            printf '#!/bin/sh\nprintf "%%s\\n" "fixture TeX"\n' >"$TEX_ARCH_BIN/$tex_command"
            chmod +x "$TEX_ARCH_BIN/$tex_command"
        done
        ;;
    *) exit 16 ;;
esac
SH
    chmod +x "$FIXTURE_BIN/uname" "$FIXTURE_BIN/curl" "$TEX_TLMGR_TEMPLATE"
}

_existing_tinytex() {
    local tex_bin="$TEST_TOOLS/tex/.TinyTeX/bin/fixture-linux"
    mkdir -p "$tex_bin"
    cp "$TEX_TLMGR_TEMPLATE" "$tex_bin/tlmgr"
}

_run_latex() {
    run env HOME="$TEST_HOME" DF_TOOLS_ROOT="$TEST_TOOLS" DF_USE_PLAT=0 \
        PATH="$FIXTURE_BIN:$PATH" DF_MODE=install "$@" \
        bash "$REPO_ROOT/install/latex.sh"
}

@test "existing TinyTeX updates its manager before installing required packages" {
    _existing_tinytex

    _run_latex

    [ "$status" -eq 0 ]
    [ "$(head -1 "$TEX_LOG")" = 'update --self' ]
    grep -Fxq 'install latexmk chktex texcount latexdiff' "$TEX_LOG"
    [ "$(grep -Fc download "$TEX_LOG")" -eq 0 ]
    [[ "$output" == *"TeX ready:"* ]]
}

@test "TinyTeX update mode performs only the manager update before baseline installation" {
    _existing_tinytex

    _run_latex DF_MODE=update

    [ "$status" -eq 0 ]
    [ "$(head -1 "$TEX_LOG")" = 'update --self' ]
    [ "$(grep -Fc -- --all "$TEX_LOG")" -eq 0 ]
}

@test "TinyTeX upgrade updates manager and packages before baseline installation once" {
    _existing_tinytex

    _run_latex DF_MODE=upgrade

    [ "$status" -eq 0 ]
    [ "$(head -1 "$TEX_LOG")" = 'update --self --all' ]
    [ "$(grep -c '^update ' "$TEX_LOG")" -eq 1 ]
    grep -Fxq 'install latexmk chktex texcount latexdiff' "$TEX_LOG"
}

@test "TinyTeX self-update failure stops before package operations" {
    _existing_tinytex

    _run_latex TEX_FAIL_UPDATE=1

    [ "$status" -ne 0 ]
    [ "$(cat "$TEX_LOG")" = 'update --self' ]
    [[ "$output" == *"tlmgr self-update failed"* ]]
    [[ "$output" != *"TeX ready:"* ]]
}

@test "TinyTeX baseline installation failure stays fatal after updating the manager" {
    _existing_tinytex

    _run_latex TEX_FAIL_BASELINE=1

    [ "$status" -ne 0 ]
    [ "$(head -1 "$TEX_LOG")" = 'update --self' ]
    [[ "$output" == *"tlmgr failed to install the required baseline packages"* ]]
}

@test "new TinyTeX installation updates its manager before installing the baseline" {
    _run_latex

    [ "$status" -eq 0 ]
    [ "$(sed -n '1p' "$TEX_LOG")" = download ]
    [ "$(sed -n '2p' "$TEX_LOG")" = 'installer <> <--no-path>' ]
    [ "$(sed -n '3p' "$TEX_LOG")" = 'update --self' ]
    grep -Fxq 'install latexmk chktex texcount latexdiff' "$TEX_LOG"
}

@test "failed TinyTeX download installer stops before manager operations" {
    _run_latex TEX_FAIL_INSTALLER=1

    [ "$status" -ne 0 ]
    [ "$(grep -c '^update ' "$TEX_LOG")" -eq 0 ]
    [[ "$output" != *"TeX ready:"* ]]
}

@test "TinyTeX installer must produce tlmgr before package operations" {
    _run_latex TEX_SKIP_TLMGR=1

    [ "$status" -ne 0 ]
    [[ "$output" == *"TinyTeX install failed (no tlmgr"* ]]
    [ "$(grep -c '^update ' "$TEX_LOG")" -eq 0 ]
}

@test "TinyTeX rerun preserves the installed baseline and verifies runtime commands" {
    _existing_tinytex
    _run_latex
    [ "$status" -eq 0 ]
    printf '#!/bin/sh\nprintf "%%s\\n" "kept baseline"\n' >"$TEX_ARCH_BIN/latexmk"

    _run_latex

    [ "$status" -eq 0 ]
    [ "$("$TEX_ARCH_BIN/latexmk" --version)" = 'kept baseline' ]
    [ "$(grep -c '^update --self$' "$TEX_LOG")" -eq 2 ]
    [ "$(grep -Fc download "$TEX_LOG")" -eq 0 ]
}

@test "TinyTeX rejects an incomplete baseline even when package installation reports success" {
    _existing_tinytex

    _run_latex TEX_MISSING_COMMAND=latexdiff

    [ "$status" -ne 0 ]
    [[ "$output" == *"TinyTeX is missing required command:"*"latexdiff"* ]]
}
