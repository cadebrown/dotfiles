#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "Node installer removes only npm prefix settings that conflict with nvm" {
    cat >"$TEST_HOME/.npmrc" <<'EOF'
# npm user policy
registry=https://registry.npmjs.org/
 prefix = /legacy/indented
prefix=/legacy/global
fund=false
; prefix=/commented/value
EOF
    chmod 644 "$TEST_HOME/.npmrc"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/node.sh"
        _reconcile_nvm_npmrc
        cat "$HOME/.npmrc"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            stat -f "%Lp" "$HOME/.npmrc"
        else
            stat -c "%a" "$HOME/.npmrc"
        fi
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [[ "$output" == *"registry=https://registry.npmjs.org/"* ]]
    [[ "$output" == *"fund=false"* ]]
    [[ "$output" == *"; prefix=/commented/value"* ]]
    [[ "$output" != *"/legacy/indented"* ]]
    [[ "$output" != *"/legacy/global"* ]]
    [[ "$output" == *$'\n600' ]]
}

@test "Node installer preserves npmrc when globalconfig needs manual migration" {
    cat >"$TEST_HOME/.npmrc" <<'EOF'
registry=https://registry.example.test/
GLOBALCONFIG = /private/npmrc
fund=false
EOF
    cp "$TEST_HOME/.npmrc" "$TEST_HOME/expected"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/node.sh"
        _reconcile_nvm_npmrc
    ' _ "$REPO"

    [ "$status" -ne 0 ]
    [[ "$output" == *"move any needed registry/auth policy"* ]]
    cmp "$TEST_HOME/.npmrc" "$TEST_HOME/expected"
}

@test "npm nvm reconciliation is idempotent and tolerates a missing file" {
    cat >"$TEST_HOME/.npmrc" <<'EOF'
registry=https://registry.npmjs.org/
fund=false
EOF
    cp "$TEST_HOME/.npmrc" "$TEST_HOME/expected"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/node.sh"
        _reconcile_nvm_npmrc
        _reconcile_nvm_npmrc
        cmp "$HOME/.npmrc" "$HOME/expected"
        HOME="$HOME/missing" _reconcile_nvm_npmrc
    ' _ "$REPO"

    [ "$status" -eq 0 ]
}
