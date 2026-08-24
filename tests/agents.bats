#!/usr/bin/env bats
# Static contracts for the agent harness. These catch upstream CLI drift before
# a bootstrap silently installs a degraded configuration.

setup() {
    REPO="$HOME/dotfiles"
}

@test "agent installers and doctor have valid shell syntax" {
    bash -n "$REPO/install/memory.sh"
    bash -n "$REPO/install/skills-sync.sh"
    bash -n "$REPO/install/codex.sh"
    bash -n "$REPO/home/dot_local/bin/executable_df-agent-doctor"
}

@test "Claude handles an empty overlay registry under macOS system Bash" {
    grep -q '"${DF_OVERLAYS\[@\]-}"' "$REPO/install/claude.sh"
}

@test "Blender version detection does not SIGPIPE under pipefail" {
    ! grep -Eq "awk .*exit" "$REPO/install/blender-mcp.sh"
}

@test "install library resolves the nvm default instead of the highest installed major" {
    local fake_home="$BATS_TEST_TMPDIR/nvm-home"
    mkdir -p "$fake_home/.local/nvm/alias"
    mkdir -p "$fake_home/.local/nvm/versions/node/v24.19.0/bin"
    mkdir -p "$fake_home/.local/nvm/versions/node/v25.9.0/bin"
    printf '24\n' > "$fake_home/.local/nvm/alias/default"

    run env HOME="$fake_home" DF_USE_PLAT=0 bash -c '
        source "$1/install/_lib.sh"
        printf "%s\n" "${PATH%%:*}"
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "$fake_home/.local/nvm/versions/node/v24.19.0/bin" ]
}

@test "remote bootstrap may defer the missing PLAT spec check only explicitly" {
    local fake_repo="$BATS_TEST_TMPDIR/deferred-plat"
    mkdir -p "$fake_repo/install" "$fake_repo/packages"
    cp "$REPO/install/_lib.sh" "$fake_repo/install/_lib.sh"

    run env HOME="$BATS_TEST_TMPDIR/home" DF_USE_PLAT=1 bash -c \
        'source "$1/install/_lib.sh"' _ "$fake_repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"DF_USE_PLAT=1 but no matching plat spec"* ]]

    run env HOME="$BATS_TEST_TMPDIR/home" DF_USE_PLAT=1 \
        DF_DEFER_PLAT_REQUIRE=1 bash -c \
        'source "$1/install/_lib.sh"; printf "%s\n" "$DF_USE_PLAT"' _ "$fake_repo"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "agent doctor audits the non-executable skill installer through bash" {
    grep -Fq '[[ -f "$_repo/install/skills-sync.sh" ]]' \
        "$REPO/home/dot_local/bin/executable_df-agent-doctor"
    grep -Fq '_check "skill registry" bash "$' \
        "$REPO/home/dot_local/bin/executable_df-agent-doctor"
}

@test "agent doctor uses system Bash around the macOS 5.3 heredoc bug" {
    grep -Fq 'exec /bin/bash "$0" "$@"' \
        "$REPO/home/dot_local/bin/executable_df-agent-doctor"
}

@test "cass indexes semantic vectors with bounded periodic refreshes" {
    # HNSW build dropped deliberately (commit 995cde2) — plain semantic index.
    grep -q 'index --full --semantic' "$REPO/install/memory.sh"
    grep -q 'index --semantic' "$REPO/install/memory.sh"
    ! grep -q -- '--build-hnsw' "$REPO/install/memory.sh"
    ! grep -Eq '"\$_cass" watch|"\$ARCH_BIN/cass" watch' "$REPO/install/memory.sh"

    plist="$REPO/home/Library/LaunchAgents/dev.cade.cass-watch.plist.tmpl"
    grep -q '<string>index</string>' "$plist"
    ! grep -q '<string>--watch</string>' "$plist"
    ! grep -q '<string>--semantic</string>' "$plist"
    grep -q '<key>StartInterval</key>' "$plist"
    grep -q '<integer>300</integer>' "$plist"
    semantic="$REPO/home/Library/LaunchAgents/dev.cade.cass-semantic.plist.tmpl"
    grep -q '<string>--semantic</string>' "$semantic"
    ! grep -q -- '--build-hnsw' "$semantic"
    grep -q '<key>StartCalendarInterval</key>' "$semantic"
    grep -q '<key>CASS_SEMANTIC_EMBEDDER</key>' "$semantic"
    grep -q '<string>minilm</string>' "$semantic"
    grep -q '<key>CASS_INDEX_STALL_ABORT_SECS</key>' "$semantic"
    grep -q 'CASS_INDEX_STALL_ABORT_SECS.*0' "$REPO/install/memory.sh"
    grep -q 'semantic index absent — deferring rebuild to dev.cade.cass-semantic' \
        "$REPO/install/memory.sh"
    ! grep -Eq 'cass (watch|index --semantic)' "$REPO/home/dot_bash_profile.tmpl"
    ! grep -Eq 'cass (watch|index --semantic)' "$REPO/home/dot_zprofile.tmpl"
}

@test "qmd persists the intended embedding model" {
    config="$REPO/home/dot_config/qmd/index.yml.tmpl"
    grep -q 'Qwen3-Embedding-0.6B-Q8_0.gguf' "$config"
    ! grep -qi 'embeddinggemma' "$config"
}

@test "clipboard configuration covers shell tmux and Neovim SSH sessions" {
    ghostty="$REPO/home/dot_config/ghostty/config"
    grep -q '^copy-on-select = clipboard$' "$ghostty"
    grep -q '^clipboard-write = allow$' "$ghostty"
    grep -q 'ssh-env,ssh-terminfo' "$ghostty"
    grep -q '^set -s set-clipboard on$' "$REPO/home/dot_tmux.conf"
    grep -q "vim.g.clipboard = 'osc52'" "$REPO/home/dot_config/nvim/init.lua"
}

@test "declared agent capabilities have package owners" {
    grep -q '^brew "yq"' "$REPO/packages/Brewfile"
    [[ -s "$REPO/packages/agent-skills.txt" ]]
    [[ -s "$REPO/packages/codex-plugins.txt" ]]
    grep -q '^plugin-eval@openai-curated$' "$REPO/packages/codex-plugins.txt"
    grep -q '^playwright-cli npx microsoft/playwright-cli playwright-cli$' \
        "$REPO/packages/agent-skills.txt"
}

@test "Codex and Claude ship bounded researcher and reviewer agents" {
    grep -q '^max_depth = 1$' "$REPO/home/dot_codex/create_private_config.toml"
    [[ -f "$REPO/home/dot_codex/agents/researcher.toml" ]]
    [[ -f "$REPO/home/dot_codex/agents/reviewer.toml" ]]
    [[ -f "$REPO/home/dot_claude/agents/researcher.md" ]]
    [[ -f "$REPO/home/dot_claude/agents/reviewer.md" ]]
}

@test "agent skill digest lock covers every declared skill" {
    local declared locked
    declared="$(mktemp)"
    locked="$(mktemp)"
    awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$REPO/packages/agent-skills.txt" | sort -u > "$declared"
    jq -r '.skills | keys[]' "$REPO/packages/agent-skills.lock.json" | sort -u > "$locked"
    run diff -u "$declared" "$locked"
    [ "$status" -eq 0 ]
}

@test "global instructions distinguish native memory and external writes" {
    local common="$REPO/home/.chezmoitemplates/agents-common.md"
    grep -q 'Harness memory' "$common"
    ! grep -q 'Auto-memory.*Claude Code only' "$common"
    grep -q 'external writes' "$common"
}
