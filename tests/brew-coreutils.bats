#!/usr/bin/env bats

fixture_os() {
    local fixture_bin="$BATS_TEST_TMPDIR/os-bin"
    mkdir -p "$fixture_bin"
    cat >"$fixture_bin/uname" <<'SH'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = -s ]; then
    printf '%s\n' "$DF_FIXTURE_OS"
else
    exec /usr/bin/uname "$@"
fi
SH
    chmod +x "$fixture_bin/uname"
    export DF_FIXTURE_OS="$1"
    export PATH="$fixture_bin:$PATH"
}

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    FORMULA="$TEST_HOME/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/c/coreutils.rb"
    TEST_PREFIX="$BATS_TEST_TMPDIR/prefix"
    TEST_LOG="$BATS_TEST_TMPDIR/brew.log"
    TEST_STATE="$BATS_TEST_TMPDIR/repaired"
    mkdir -p "$(dirname "$FORMULA")" "$TEST_PREFIX/bin"

    export BREW_TEST_INSTALLED=1
    export BREW_TEST_HEALTHY=1
    export BREW_TEST_REPAIR_SUCCEEDS=1
    export BREW_TEST_REINSTALL_SUCCEEDS=1
    export BREW_TEST_DISAPPEARS=0
    export BREW_TEST_LOG="$TEST_LOG"
    export BREW_TEST_STATE="$TEST_STATE"
    fixture_os Linux
}

_write_formula() {
    cat >"$FORMULA" <<'RUBY'
class Coreutils < Formula
  on_linux do
    depends_on "acl"
    depends_on "attr"
  end

  def install
    args = %w[
      --program-prefix=g
      --with-libgmp
      --without-selinux
    ]
  end
end
RUBY
}

_run_patch() {
    run env HOME="$TEST_HOME" DF_TOOLS_ROOT="$TEST_HOME/.local" DF_USE_PLAT=0 \
        bash "$REPO_ROOT/install/patch-homebrew-coreutils.sh"
}

_run_reconcile() {
    run bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            printf "%s\\n" "$*" >>"$BREW_TEST_LOG"
            case "$*" in
                "list --formula")
                    if [[ "$BREW_TEST_INSTALLED" == "1" && ! -f "$BREW_TEST_STATE.disappeared" ]]; then
                        printf "%s\\n" coreutils
                    fi
                    return 0
                    ;;
                "reinstall --build-from-source coreutils")
                    [[ "$BREW_TEST_REINSTALL_SUCCEEDS" == "1" ]] || return 7
                    [[ "$BREW_TEST_DISAPPEARS" == "1" ]] && : >"$BREW_TEST_STATE.disappeared"
                    [[ "$BREW_TEST_REPAIR_SUCCEEDS" == "1" ]] && : >"$BREW_TEST_STATE"
                    return 0
                    ;;
                *)
                    printf "unexpected brew command: %s\\n" "$*" >&2
                    return 2
                    ;;
            esac
        }
        _reconcile_brew_coreutils "$2"
    ' _ "$REPO_ROOT" "$TEST_PREFIX"
}

@test "coreutils formula patch is idempotent" {
    _write_formula

    _run_patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Patched: coreutils builds against declared openssl@4"* ]]
    grep -Fxq '    depends_on "openssl@4"' "$FORMULA"
    grep -Fxq '      --with-openssl=yes' "$FORMULA"

    _run_patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
}

@test "coreutils formula patch rejects an unknown formula shape" {
    printf '%s\n' 'class Coreutils < Formula' >"$FORMULA"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"patch target not found"* ]]
    [[ "$output" == *"Linux dependency block"* ]]
    [[ "$output" == *"configure arguments"* ]]
}

@test "coreutils formula patch honors master and individual skip gates" {
    _write_formula

    run env HOME="$TEST_HOME" DF_TOOLS_ROOT="$TEST_HOME/.local" DF_USE_PLAT=0 \
        DF_PATCH_BREW_ALL=0 bash "$REPO_ROOT/install/patch-homebrew-coreutils.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DF_PATCH_BREW_ALL=0"* ]]
    ! grep -Fq 'depends_on "openssl@4"' "$FORMULA"

    run env HOME="$TEST_HOME" DF_TOOLS_ROOT="$TEST_HOME/.local" DF_USE_PLAT=0 \
        DF_PATCH_BREW_COREUTILS=0 bash "$REPO_ROOT/install/patch-homebrew-coreutils.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"DF_PATCH_BREW_COREUTILS=0"* ]]
    ! grep -Fq 'depends_on "openssl@4"' "$FORMULA"
}

@test "healthy coreutils sha256sum is not rebuilt" {
    cat >"$TEST_PREFIX/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
[[ "$1" == - ]] || exit 2
[[ "$(cat)" == abc ]] || exit 2
printf '%s\n' 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  -'
SH
    chmod +x "$TEST_PREFIX/bin/sha256sum"

    _run_reconcile

    [ "$status" -eq 0 ]
    ! grep -Fq 'reinstall --build-from-source coreutils' "$TEST_LOG"
}

@test "broken coreutils sha256sum is rebuilt from source and rechecked" {
    cat >"$TEST_PREFIX/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
if [[ "${BREW_TEST_HEALTHY:-1}" == "1" || -f "$BREW_TEST_STATE" ]]; then
    printf '%s\n' 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  -'
else
    printf '%s\n' 'sha256sum: error while loading shared libraries: libcrypto.so.3' >&2
    exit 127
fi
SH
    chmod +x "$TEST_PREFIX/bin/sha256sum"
    export BREW_TEST_HEALTHY=0

    _run_reconcile

    [ "$status" -eq 0 ]
    grep -Fxq 'reinstall --build-from-source coreutils' "$TEST_LOG"
    [ -f "$TEST_STATE" ]
}

@test "failed coreutils source rebuild leaves the runtime check failing" {
    cat >"$TEST_PREFIX/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'sha256sum: error while loading shared libraries: libcrypto.so.3' >&2
exit 127
SH
    chmod +x "$TEST_PREFIX/bin/sha256sum"
    export BREW_TEST_HEALTHY=0
    export BREW_TEST_REPAIR_SUCCEEDS=0

    _run_reconcile

    [ "$status" -ne 0 ]
    [[ "$output" == *"still broken after its source rebuild"* ]]
    grep -Fxq 'reinstall --build-from-source coreutils' "$TEST_LOG"
}

@test "failed coreutils source rebuild command stops reconciliation" {
    cat >"$TEST_PREFIX/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
exit 127
SH
    chmod +x "$TEST_PREFIX/bin/sha256sum"
    export BREW_TEST_REINSTALL_SUCCEEDS=0

    _run_reconcile

    [ "$status" -ne 0 ]
    grep -Fxq 'reinstall --build-from-source coreutils' "$TEST_LOG"
    [[ "$output" != *"still broken after its source rebuild"* ]]
}

@test "coreutils disappearing during rebuild fails the required postcondition" {
    cat >"$TEST_PREFIX/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
exit 127
SH
    chmod +x "$TEST_PREFIX/bin/sha256sum"
    export BREW_TEST_DISAPPEARS=1

    _run_reconcile

    [ "$status" -ne 0 ]
    [[ "$output" == *"Required coreutils is not installed"* ]]
}

@test "missing coreutils is left for Bundle" {
    export BREW_TEST_INSTALLED=0

    _run_reconcile

    [ "$status" -eq 0 ]
    ! grep -Fq 'reinstall --build-from-source coreutils' "$TEST_LOG"
}

@test "coreutils reconciliation brackets Bundle when its patch is enabled" {
    local first_reconcile bundle_line last_reconcile
    first_reconcile=$(grep -n '^    _reconcile_brew_coreutils "\$_REAL_BREW_PREFIX"$' \
        "$REPO_ROOT/install/linux-packages.sh" | head -1 | cut -d: -f1)
    bundle_line=$(grep -n '^_run_brew_bundle "\$_BREWFILE_TMP" ' \
        "$REPO_ROOT/install/linux-packages.sh" | cut -d: -f1)
    last_reconcile=$(grep -n '^    _reconcile_brew_coreutils "\$_REAL_BREW_PREFIX"$' \
        "$REPO_ROOT/install/linux-packages.sh" | tail -1 | cut -d: -f1)

    [ "$first_reconcile" -lt "$bundle_line" ]
    [ "$bundle_line" -lt "$last_reconcile" ]
}
