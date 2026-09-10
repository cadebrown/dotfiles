#!/usr/bin/env bats

@test "Codex history import copies portable records without overwriting local continuations" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/codex-history-test.py"
    [ "$status" -eq 0 ]
}

@test "Codex full backup preserves raw state and rejects incomplete snapshots" {
    run uv run --no-project python "$BATS_TEST_DIRNAME/codex-backup-test.py"
    [ "$status" -eq 0 ]
}

@test "Codex backup command does not prepare or repair an unsafe source runtime" {
    local legacy="$BATS_TEST_TMPDIR/legacy" backup="$BATS_TEST_TMPDIR/backup"
    mkdir -p "$legacy/.codex" "$BATS_TEST_TMPDIR/external"
    printf 'damaged raw database\n' > "$BATS_TEST_TMPDIR/external/state_5.sqlite"
    ln -s "$BATS_TEST_TMPDIR/external/state_5.sqlite" "$legacy/.codex/state_5.sqlite"
    run env HOME="$legacy" CODEX_HOME="$legacy/.codex" DF_USE_PLAT=0 \
        bash "$BATS_TEST_DIRNAME/../install/codex.sh" backup "$legacy/.codex" "$backup"
    [ "$status" -eq 0 ]
    [ -L "$legacy/.codex/state_5.sqlite" ]
    [ ! -e "$legacy/.codex/config.toml" ]
    cmp "$BATS_TEST_TMPDIR/external/state_5.sqlite" "$backup/sources/codex/tree/state_5.sqlite"
    [ "$(jq -r .status "$backup/manifest.json")" = complete ]
}
