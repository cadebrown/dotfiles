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

@test "npm entrypoint validation handles scoped packages and object bin metadata" {
    local node_bin
    node_bin="$(command -v node 2>/dev/null || true)"
    if [[ -z "$node_bin" ]]; then
        node_bin="$(printf '%s\n' "$HOME"/.local/*/nvm/versions/node/*/bin/node \
            | tail -1)"
    fi
    [ -x "$node_bin" ]
    mkdir -p "$TEST_HOME/root/@scope/tool" "$TEST_HOME/bin"
    cat >"$TEST_HOME/root/@scope/tool/package.json" <<'EOF'
{"name":"@scope/tool","bin":{"tool":"cli.js","tool-admin":"admin.js"}}
EOF
    touch "$TEST_HOME/bin/tool"
    chmod +x "$TEST_HOME/bin/tool"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        PATH="$(dirname "$node_bin"):$PATH" bash -c '
        source "$1/install/node.sh"
        _npm_missing_bins @scope/tool "$HOME/root" "$HOME/bin"
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | tail -1)" = "tool-admin" ]
}

@test "npm entrypoint validation rejects missing package bin metadata" {
    mkdir -p "$TEST_HOME/root/no-cli" "$TEST_HOME/bin"
    printf '%s\n' '{"name":"no-cli"}' >"$TEST_HOME/root/no-cli/package.json"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/node.sh"
        _npm_missing_bins no-cli "$HOME/root" "$HOME/bin"
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "<package-bin-metadata>" ]
}

@test "npm entrypoint validation rejects an executable that cannot start" {
    local node_bin
    node_bin="$(command -v node 2>/dev/null || true)"
    if [[ -z "$node_bin" ]]; then
        node_bin="$(printf '%s\n' "$HOME"/.local/*/nvm/versions/node/*/bin/node \
            | tail -1)"
    fi
    mkdir -p "$TEST_HOME/root/tool" "$TEST_HOME/bin"
    printf '%s\n' '{"name":"tool","bin":{"tool":"cli.js"}}' \
        > "$TEST_HOME/root/tool/package.json"
    cat > "$TEST_HOME/bin/tool" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$TEST_HOME/bin/tool"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 DF_TOOL_SMOKE_TIMEOUT=0.2 \
        LC_ALL=C LANG=C PATH="$(dirname "$node_bin"):$PATH" bash -c '
        source "$1/install/node.sh"
        _npm_missing_bins tool "$HOME/root" "$HOME/bin"
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "tool" ]
}

@test "npm entrypoint validation accepts pyright langserver's exact transport error" {
    local node_bin
    node_bin="$(command -v node 2>/dev/null || true)"
    if [[ -z "$node_bin" ]]; then
        node_bin="$(printf '%s\n' "$HOME"/.local/*/nvm/versions/node/*/bin/node \
            | tail -1)"
    fi
    mkdir -p "$TEST_HOME/root/pyright" "$TEST_HOME/bin"
    printf '%s\n' '{"name":"pyright","bin":{"pyright-langserver":"index.js"}}' \
        > "$TEST_HOME/root/pyright/package.json"
    cat > "$TEST_HOME/bin/pyright-langserver" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "Error: Connection input stream is not set. Use '--stdio'" >&2
exit 1
EOF
    chmod +x "$TEST_HOME/bin/pyright-langserver"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        PATH="$(dirname "$node_bin"):$PATH" bash -c '
        source "$1/install/node.sh"
        _npm_missing_bins pyright "$HOME/root" "$HOME/bin"
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Node failure trap restarts qmd and preserves the original failure" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/node.sh"
        _qmd_stopped=1
        qmd_daemon_start() { touch "$HOME/qmd-started"; }
        _qmd_wait_healthy() { return 0; }
        trap _restart_qmd_after_node_exit EXIT
        exit 42
    ' _ "$REPO"

    [ "$status" -eq 42 ]
    [ -f "$TEST_HOME/qmd-started" ]
}
