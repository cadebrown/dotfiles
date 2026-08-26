#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_PREFIX="$BATS_TEST_TMPDIR/prefix"
    TEST_LOG="$BATS_TEST_TMPDIR/brew.log"
    TEST_STATE="$BATS_TEST_TMPDIR/repaired"
    mkdir -p "$TEST_PREFIX/bin"

    cat >"$TEST_PREFIX/bin/clang" <<'SH'
#!/usr/bin/env bash
if [[ "${BREW_TEST_CLANG_HEALTHY:-1}" == "1" || -f "$BREW_TEST_STATE" ]]; then
    printf '%s\n' 'clang version test'
    exit 0
fi
printf '%s\n' 'clang: error while loading shared libraries: libz3.so.old' >&2
exit 127
SH
    chmod +x "$TEST_PREFIX/bin/clang"

    export BREW_TEST_INSTALLED=1
    export BREW_TEST_OUTDATED=0
    export BREW_TEST_LINKAGE_HEALTHY=1
    export BREW_TEST_CLANG_HEALTHY=1
    export BREW_TEST_REPAIR_SUCCEEDS=1
    export BREW_TEST_LIST_ERROR=0
    export BREW_TEST_LOG="$TEST_LOG"
    export BREW_TEST_STATE="$TEST_STATE"
}

_run_helper() {
    local helper="$1" upgrade_mode="${2:-0}"
    run bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            printf "%s\n" "$*" >>"$BREW_TEST_LOG"
            case "$*" in
                "list --formula")
                    [[ "$BREW_TEST_LIST_ERROR" == "0" ]] || return 2
                    [[ "$BREW_TEST_INSTALLED" == "1" ]] && printf "%s\n" "llvm"
                    return 0
                    ;;
                "outdated --formula llvm")
                    if [[ "$BREW_TEST_OUTDATED" == "1" ]]; then
                        printf "%s\n" "llvm"
                    fi
                    return 0
                    ;;
                "upgrade llvm"|"reinstall llvm")
                    if [[ "$BREW_TEST_REPAIR_SUCCEEDS" == "1" ]]; then
                        : >"$BREW_TEST_STATE"
                    fi
                    ;;
                "linkage --test llvm")
                    [[ "$BREW_TEST_LINKAGE_HEALTHY" == "1" || -f "$BREW_TEST_STATE" ]]
                    ;;
                *)
                    printf "unexpected brew command: %s\n" "$*" >&2
                    return 2
                    ;;
            esac
        }
        case "$3" in
            reconcile) _reconcile_brew_llvm_z3 "$2" "$4" ;;
            verify) _verify_brew_llvm "$2" 1 ;;
        esac
    ' _ "$REPO_ROOT" "$TEST_PREFIX" "$helper" "$upgrade_mode"
}

_run_reconcile() {
    _run_helper reconcile "$1"
}

@test "outdated LLVM is upgraded before Bundle in upgrade mode" {
    export BREW_TEST_OUTDATED=1

    _run_reconcile 1

    [ "$status" -eq 0 ]
    grep -Fxq 'upgrade llvm' "$TEST_LOG"
    ! grep -Fxq 'reinstall llvm' "$TEST_LOG"
}

@test "current LLVM with broken Z3 linkage is reinstalled" {
    export BREW_TEST_LINKAGE_HEALTHY=0
    export BREW_TEST_CLANG_HEALTHY=0

    _run_reconcile 1

    [ "$status" -eq 0 ]
    grep -Fxq 'reinstall llvm' "$TEST_LOG"
    ! grep -Fxq 'upgrade llvm' "$TEST_LOG"
}

@test "healthy LLVM is not mutated" {
    _run_reconcile 1

    [ "$status" -eq 0 ]
    ! grep -Eq '^(upgrade|reinstall) llvm$' "$TEST_LOG"
}

@test "install-only mode repairs broken LLVM without upgrading healthy LLVM" {
    export BREW_TEST_OUTDATED=1
    export BREW_TEST_LINKAGE_HEALTHY=0
    export BREW_TEST_CLANG_HEALTHY=0

    _run_reconcile 0

    [ "$status" -eq 0 ]
    grep -Fxq 'reinstall llvm' "$TEST_LOG"
    ! grep -Fxq 'upgrade llvm' "$TEST_LOG"
}

@test "missing LLVM is left for Bundle to install" {
    export BREW_TEST_INSTALLED=0

    _run_reconcile 1

    [ "$status" -eq 0 ]
    ! grep -Eq '^(upgrade|reinstall|linkage) ' "$TEST_LOG"
}

@test "failed LLVM repair stops before source builds" {
    export BREW_TEST_LINKAGE_HEALTHY=0
    export BREW_TEST_CLANG_HEALTHY=0
    export BREW_TEST_REPAIR_SUCCEEDS=0

    _run_reconcile 1

    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]
}

@test "required postcondition rejects missing LLVM and list errors" {
    export BREW_TEST_INSTALLED=0

    _run_helper verify

    [ "$status" -ne 0 ]
    [[ "$output" == *"Required unversioned LLVM is not installed"* ]]

    export BREW_TEST_INSTALLED=1
    export BREW_TEST_LIST_ERROR=1

    _run_helper verify

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not list installed Homebrew formulae"* ]]
}

@test "LLVM reconciliation and verification bracket Bundle" {
    local reconcile_line bundle_line verify_line
    reconcile_line=$(grep -n '^_reconcile_brew_llvm_z3 ' "$REPO_ROOT/install/linux-packages.sh" | cut -d: -f1)
    bundle_line=$(grep -n '^_run_brew_bundle "\$_BREWFILE_TMP" ' \
        "$REPO_ROOT/install/linux-packages.sh" | cut -d: -f1)
    verify_line=$(grep -n '^if ! _verify_brew_llvm "\$_REAL_BREW_PREFIX" 1; then$' \
        "$REPO_ROOT/install/linux-packages.sh" | cut -d: -f1)

    [ "$reconcile_line" -lt "$bundle_line" ]
    [ "$bundle_line" -lt "$verify_line" ]
}
