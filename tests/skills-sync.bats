#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURE="$BATS_TEST_TMPDIR/fixture"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    CALLS="$BATS_TEST_TMPDIR/npx-calls"
    # Hosted runners export XDG paths independently of HOME. Keep chezmoi's
    # config and state inside the same disposable home as the bootstrap fixture.
    export XDG_CONFIG_HOME="$FAKE_HOME/.config"
    export XDG_DATA_HOME="$FAKE_HOME/.local/share"
    # This fixture models the default ~/.agents receipt layout, not the
    # alternative XDG_STATE_HOME/skills layout supported by skills-sync.
    unset XDG_STATE_HOME

    mkdir -p "$FIXTURE/install" "$FIXTURE/packages" "$FIXTURE/home/.chezmoitemplates" \
        "$FAKE_HOME/.claude/skills/example" "$FAKE_HOME/.agents" "$STUB_BIN"
    cp "$REPO/install/_lib.sh" "$FIXTURE/install/_lib.sh"
    cp "$REPO/install/_runtime-paths.sh" "$FIXTURE/install/_runtime-paths.sh"
    cp "$REPO/home/.chezmoitemplates/compiler-cache.sh" "$FIXTURE/home/.chezmoitemplates/"
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

@test "upgrade forces self-installed skills to overwrite existing content" {
    mv "$FAKE_HOME/.claude/skills/example" "$FAKE_HOME/.claude/skills/glab"
    grep '^glab self ' "$REPO/packages/agent-skills.txt" \
        > "$FIXTURE/packages/agent-skills.txt"
    jq -n --arg hash "$(tree_hash "$FAKE_HOME/.claude/skills/glab")" \
        '{version: 1, skills: {glab: $hash}}' \
        > "$FIXTURE/packages/agent-skills.lock.json"
    jq -n '{version: 3, skills: {}}' > "$FAKE_HOME/.agents/.skill-lock.json"

    cat > "$STUB_BIN/glab" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "skills install --global --force" ]]
printf '%s\n' '---' 'name: glab' '---' 'version 2' \
    > "$HOME/.claude/skills/glab/SKILL.md"
EOF
    chmod 755 "$STUB_BIN/glab"

    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 DF_MODE=upgrade \
        CALLS="$CALLS" PATH="$STUB_BIN:$PATH" \
        bash "$FIXTURE/install/skills-sync.sh"

    [ "$status" -eq 0 ]
    grep -Fxq 'version 2' "$FAKE_HOME/.claude/skills/glab/SKILL.md"
}

@test "sync archives obsolete generated Pi links and preserves other links" {
    mkdir -p "$FAKE_HOME/.pi/agent/skills"
    ln -s ../../../.agents/skills/retired "$FAKE_HOME/.pi/agent/skills/retired"
    ln -s ../../../.agents/skills/example "$FAKE_HOME/.pi/agent/skills/example"
    ln -s /missing/personal-skill "$FAKE_HOME/.pi/agent/skills/personal"

    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 PATH="$STUB_BIN:$PATH" \
        bash "$FIXTURE/install/skills-sync.sh"
    [ "$status" -eq 0 ]
    [ ! -L "$FAKE_HOME/.pi/agent/skills/retired" ]
    [ -L "$FAKE_HOME/.pi/agent/skills/example" ]
    [ -L "$FAKE_HOME/.pi/agent/skills/personal" ]
    run bash -c 'compgen -G "$1/.local/state/dotfiles/skill-backups/*/pi-links/retired"' _ "$FAKE_HOME"
    [ "$status" -eq 0 ]
}

@test "sync adopts vendored skills without overwriting their installed contents" {
    mkdir -p "$FIXTURE/home/dot_claude/skills/adopted" "$FAKE_HOME/.claude/skills/adopted"
    printf 'managed source\n' > "$FIXTURE/home/dot_claude/skills/adopted/SKILL.md"
    printf 'prior install\n' > "$FAKE_HOME/.claude/skills/adopted/SKILL.md"
    jq '.skills.adopted = {skillFolderHash: "prior"}' "$FAKE_HOME/.agents/.skill-lock.json" > "$BATS_TEST_TMPDIR/receipt"
    mv "$BATS_TEST_TMPDIR/receipt" "$FAKE_HOME/.agents/.skill-lock.json"

    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 PATH="$STUB_BIN:$PATH" \
        bash "$FIXTURE/install/skills-sync.sh"
    [ "$status" -eq 0 ]
    jq -e '.skills.adopted == null and .skills.example != null' "$FAKE_HOME/.agents/.skill-lock.json"
    grep -Fxq 'prior install' "$FAKE_HOME/.claude/skills/adopted/SKILL.md"
    run bash -c 'compgen -G "$1/.local/state/dotfiles/skill-backups/*/adopted/SKILL.md"' _ "$FAKE_HOME"
    [ "$status" -eq 0 ]
}

@test "chezmoi archives prior skill edits before replacing them on apply" {
    mkdir -p "$FIXTURE/home/dot_claude/skills/adopted" "$FAKE_HOME/.claude/skills/adopted"
    printf 'managed source\n' > "$FIXTURE/home/dot_claude/skills/adopted/SKILL.md"
    printf 'original local edits\n' > "$FAKE_HOME/.claude/skills/adopted/SKILL.md"
    cp "$REPO/home/run_onchange_before_skill-ownership.sh.tmpl" "$FIXTURE/home/"
    jq '.skills.adopted = {skillFolderHash: "prior"}' "$FAKE_HOME/.agents/.skill-lock.json" > "$BATS_TEST_TMPDIR/receipt"
    mv "$BATS_TEST_TMPDIR/receipt" "$FAKE_HOME/.agents/.skill-lock.json"
    printf '[data]\n' > "$BATS_TEST_TMPDIR/chezmoi.toml"

    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 PATH="$STUB_BIN:$PATH" \
        chezmoi --source "$FIXTURE/home" --destination "$FAKE_HOME" \
        --config "$BATS_TEST_TMPDIR/chezmoi.toml" \
        --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" apply --force
    [ "$status" -eq 0 ]
    grep -Fxq 'managed source' "$FAKE_HOME/.claude/skills/adopted/SKILL.md"
    local archived
    archived="$(printf '%s\n' "$FAKE_HOME"/.local/state/dotfiles/skill-backups/*/adopted/SKILL.md)"
    grep -Fxq 'original local edits' "$archived"
    jq -e '.skills.adopted == null and .skills.example != null' "$FAKE_HOME/.agents/.skill-lock.json"
    [ ! -f "$CALLS" ]
    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 \
        chezmoi --source "$FIXTURE/home" --destination "$FAKE_HOME" \
        --config "$BATS_TEST_TMPDIR/chezmoi.toml" \
        --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" diff --exclude=scripts
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "bootstrap archives skill edits before its scripts-excluded chezmoi apply" {
    mkdir -p "$FIXTURE/home/dot_claude/skills/adopted" "$FAKE_HOME/.claude/skills/adopted"
    printf 'managed source\n' > "$FIXTURE/home/dot_claude/skills/adopted/SKILL.md"
    printf 'original local edits\n' > "$FAKE_HOME/.claude/skills/adopted/SKILL.md"
    printf '#!/bin/sh\nexit 91\n' > "$FIXTURE/home/run_before_should-not-run.sh"
    jq '.skills.adopted = {skillFolderHash: "prior"}' "$FAKE_HOME/.agents/.skill-lock.json" > "$BATS_TEST_TMPDIR/receipt"
    mv "$BATS_TEST_TMPDIR/receipt" "$FAKE_HOME/.agents/.skill-lock.json"
    awk '/^log_section "2 — dotfiles/ {capture=1} capture {print} /^log_okay "Dotfiles applied"/ {exit}' \
        "$REPO/bootstrap.sh" > "$BATS_TEST_TMPDIR/dotfiles-phase.sh"

    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 PATH="$STUB_BIN:$PATH" \
        DF_PATH="$FIXTURE" DF_INSTALL_DIR="$FIXTURE/install" \
        DF_NAME="Test User" DF_EMAIL="test@example.com" CHEZMOI_BIN="$(command -v chezmoi)" \
        bash -eu -c '
            log_section() { :; }; log_info() { :; }; log_okay() { :; }
            ensure_dir() { mkdir -p "$1"; }
            source "$1"
        ' _ "$BATS_TEST_TMPDIR/dotfiles-phase.sh"
    [ "$status" -eq 0 ]
    grep -Fxq 'managed source' "$FAKE_HOME/.claude/skills/adopted/SKILL.md"
    local archived
    archived="$(printf '%s\n' "$FAKE_HOME"/.local/state/dotfiles/skill-backups/*/adopted/SKILL.md)"
    grep -Fxq 'original local edits' "$archived"
    [ ! -f "$CALLS" ]
    run env HOME="$FAKE_HOME" DF_USE_PLAT=0 chezmoi diff --exclude=scripts
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
