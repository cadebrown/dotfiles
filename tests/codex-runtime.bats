#!/usr/bin/env bats

setup() {
    export REPO="${REPO:-$BATS_TEST_DIRNAME/..}"
    export RUNTIME_HOME="$BATS_TEST_TMPDIR/runtime/codex"
    export LEGACY_HOME="$BATS_TEST_TMPDIR/legacy-home"
    mkdir -p "$LEGACY_HOME/.codex"
}

@test "Codex runtime seeds only config and auth from the legacy home" {
    printf '%s\n' 'model = "preserved-choice"' > "$LEGACY_HOME/.codex/config.toml"
    printf '%s\n' '{"token":"not-a-real-token"}' > "$LEGACY_HOME/.codex/auth.json"
    printf '%s\n' 'legacy runtime database' > "$LEGACY_HOME/.codex/state_1.sqlite"
    mkdir "$LEGACY_HOME/.codex/sessions"

    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -eq 0 ]
    [ "$(cat "$RUNTIME_HOME/config.toml")" = 'model = "preserved-choice"' ]
    [ -f "$RUNTIME_HOME/auth.json" ]
    [ ! -e "$RUNTIME_HOME/state_1.sqlite" ]
    [ ! -e "$RUNTIME_HOME/sessions" ]
    [ ! -L "$RUNTIME_HOME" ]
}

@test "Codex runtime rejects a shared filesystem before it creates state" {
    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; _codex_runtime_filesystem() { printf "%s\\n" nfs4; }; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be on a local filesystem"* ]]
    [ ! -e "$RUNTIME_HOME" ]
}

@test "Codex runtime rejects relative or broad normalized roots" {
    run env HOME="$LEGACY_HOME" CODEX_HOME='relative/codex' DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"absolute private directory"* ]]

    run env HOME="$LEGACY_HOME" CODEX_HOME="$BATS_TEST_TMPDIR/state/../codex" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be normalized"* ]]
}

@test "Codex runtime ignores legacy SQLite symlinks and accepts a local default root" {
    mkdir -p "$LEGACY_HOME/.codex/sessions" "$BATS_TEST_TMPDIR/shared-state"
    ln -s "$BATS_TEST_TMPDIR/shared-state/state_1.sqlite" "$LEGACY_HOME/.codex/state_1.sqlite"

    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -eq 0 ]
    [ -L "$LEGACY_HOME/.codex/state_1.sqlite" ]

    local default_home="$BATS_TEST_TMPDIR/default-home"
    mkdir "$default_home"
    run env HOME="$default_home" DF_USE_PLAT=0 \
        bash -c 'unset CODEX_HOME DF_STATE_ROOT; source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare; test "$CODEX_HOME" = "$HOME/.codex"'
    [ "$status" -eq 0 ]
}

@test "Codex runtime rejects symlinked SQLite state in its selected root" {
    mkdir -p "$RUNTIME_HOME" "$BATS_TEST_TMPDIR/shared-state"
    ln -s "$BATS_TEST_TMPDIR/shared-state/state_1.sqlite" "$RUNTIME_HOME/state_1.sqlite"
    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"symlinked runtime asset or SQLite database"* ]]
}

@test "Codex runtime rejects a writable untrusted parent" {
    local unsafe_parent="$BATS_TEST_TMPDIR/unsafe-parent"
    mkdir "$unsafe_parent"
    chmod 777 "$unsafe_parent"
    run env HOME="$LEGACY_HOME" CODEX_HOME="$unsafe_parent/codex" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"writable by an untrusted user"* ]]
}

@test "Codex runtime allows a private child under a sticky system boundary" {
    local sticky_root
    sticky_root="$(mktemp -d /tmp/codex-runtime.XXXXXX)"
    run env HOME="$LEGACY_HOME" CODEX_HOME="$sticky_root/codex" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -eq 0 ]
    [ ! -L "$sticky_root/codex" ]
}

@test "Codex runtime rejects a symlinked selected root and external sqlite override" {
    mkdir -p "$BATS_TEST_TMPDIR/actual-root" "$BATS_TEST_TMPDIR/external-sqlite" "$(dirname "$RUNTIME_HOME")"
    ln -s "$BATS_TEST_TMPDIR/actual-root" "$RUNTIME_HOME"
    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be a real directory, not a symlink"* ]]

    run env HOME="$LEGACY_HOME" CODEX_HOME="$BATS_TEST_TMPDIR/other-runtime" CODEX_SQLITE_HOME="$BATS_TEST_TMPDIR/external-sqlite" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"sqlite_home must equal CODEX_HOME"* ]]
}

@test "Codex runtime fails closed on malformed TOML sqlite configuration" {
    mkdir -p "$RUNTIME_HOME"
    printf '%s\n' 'sqlite_home = [not valid' > "$RUNTIME_HOME/config.toml"
    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/_lib.sh"; source "$REPO/install/codex-runtime.sh"; codex_runtime_prepare'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not parse Codex TOML"* ]]
}

@test "Codex runtime leaves scratch-managed legacy Codex links unchanged" {
    local scratch="$BATS_TEST_TMPDIR/scratch"
    mkdir -p "$scratch/.paths/.codex" "$LEGACY_HOME/.codex"
    ln -s "$scratch/.paths/.codex" "$LEGACY_HOME/.codex/sessions"
    printf '%s\n' old-backup > "$scratch/.paths/.codex/db-backups.txt"

    run env HOME="$LEGACY_HOME" DF_SCRATCH="$scratch" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash "$REPO/install/scratch.sh"
    [ "$status" -eq 0 ]
    [ -L "$LEGACY_HOME/.codex/sessions" ]
    [ "$(cat "$scratch/.paths/.codex/db-backups.txt")" = old-backup ]
}

@test "Codex config sync renders managed assets in the selected runtime root" {
    printf '%s\n' 'model = "preserved-choice"' > "$LEGACY_HOME/.codex/config.toml"

    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash -c 'source "$REPO/install/codex.sh"; codex_runtime_prepare; _sync_config'
    [ "$status" -eq 0 ]
    [ -f "$RUNTIME_HOME/AGENTS.md" ]
    [ -f "$RUNTIME_HOME/rules/dotfiles.rules" ]
    [ -f "$RUNTIME_HOME/agents/coder.toml" ]
    [ -f "$RUNTIME_HOME/deep.config.toml" ]
    grep -q '^model = "preserved-choice"$' "$RUNTIME_HOME/config.toml"
    [ ! -e "$RUNTIME_HOME/sessions" ]
}

@test "sync-runtime completes config and hook projection without plugin reconciliation" {
    run env HOME="$LEGACY_HOME" CODEX_HOME="$RUNTIME_HOME" DF_STATE_ROOT="$BATS_TEST_TMPDIR/state" DF_USE_PLAT=0 \
        bash "$REPO/install/codex.sh" sync-runtime
    [ "$status" -eq 0 ]
    [ -f "$RUNTIME_HOME/config.toml" ]
    [ -f "$RUNTIME_HOME/hooks.json" ]
    [ -x "$LEGACY_HOME/.local/bin/df-rtk-rewrite" ]
}
