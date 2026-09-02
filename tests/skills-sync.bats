#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURE="$BATS_TEST_TMPDIR/fixture"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    CALLS="$BATS_TEST_TMPDIR/npx-calls"

    mkdir -p "$FIXTURE/install" "$FIXTURE/packages" \
        "$FAKE_HOME/.claude/skills/example" "$FAKE_HOME/.agents" "$STUB_BIN"
    cp "$REPO/install/_lib.sh" "$FIXTURE/install/_lib.sh"
    cp "$REPO/install/skills-sync.sh" "$FIXTURE/install/skills-sync.sh"
    printf 'example npx owner/repo example\n' > "$FIXTURE/packages/agent-skills.txt"
    printf '%s\n' '---' 'name: example' '---' 'version 1' \
        > "$FAKE_HOME/.claude/skills/example/SKILL.md"

    INITIAL_HASH="$(tree_hash "$FAKE_HOME/.claude/skills/example")"
    jq -n --arg hash "$INITIAL_HASH" \
        '{version: 1, skills: {example: $hash}}' \
        > "$FIXTURE/packages/agent-skills.lock.json"
    jq -n --arg hash "$INITIAL_HASH" \
        '{version: 3, skills: {example: {skillFolderHash: $hash}}}' \
        > "$FAKE_HOME/.agents/.skill-lock.json"

    cat > "$STUB_BIN/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
[[ " $* " == *" skills update "* ]] || exit 97

count="$(wc -l < "$CALLS" | tr -d ' ')"
printf '%s\n' '---' 'name: example' '---' "version $(( count + 1 ))" \
    > "$HOME/.claude/skills/example/SKILL.md"

hash_tmp="$(mktemp -d)"
git init --bare -q "$hash_tmp/repo"
GIT_DIR="$hash_tmp/repo" GIT_WORK_TREE="$HOME/.claude/skills/example" git add -Af .
hash="$(GIT_DIR="$hash_tmp/repo" git write-tree)"

receipt="$HOME/.agents/.skill-lock.json"
jq --arg hash "$hash" '.skills.example.skillFolderHash = $hash' "$receipt" \
    > "$receipt.tmp"
mv "$receipt.tmp" "$receipt"
EOF
    chmod 755 "$STUB_BIN/npx"
}

tree_hash() {
    local skill_dir="$1" hash_tmp
    hash_tmp="$(mktemp -d)"
    git init --bare -q "$hash_tmp/repo"
    GIT_DIR="$hash_tmp/repo" GIT_WORK_TREE="$skill_dir" git add -Af .
    GIT_DIR="$hash_tmp/repo" git write-tree
}

run_upgrade() {
    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 DF_MODE=upgrade \
        CALLS="$CALLS" PATH="$STUB_BIN:$PATH" \
        bash "$FIXTURE/install/skills-sync.sh"
    [ "$status" -eq 0 ]
}

@test "consecutive upgrades advance skills using the mutable install receipt" {
    run_upgrade
    grep -Fxq 'version 2' "$FAKE_HOME/.claude/skills/example/SKILL.md"

    run_upgrade
    grep -Fxq 'version 3' "$FAKE_HOME/.claude/skills/example/SKILL.md"
    [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 2 ]
}

@test "upgrade preserves content changed after the last installed receipt" {
    run_upgrade
    printf '%s\n' 'local edit' >> "$FAKE_HOME/.claude/skills/example/SKILL.md"

    run_upgrade
    grep -Fxq 'local edit' "$FAKE_HOME/.claude/skills/example/SKILL.md"
    [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
    [[ "$output" == *"preserve  example (locally modified since last install)"* ]]
}
