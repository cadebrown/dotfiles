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
    bash -n "$REPO/install/entire.sh"
    bash -n "$REPO/home/dot_local/bin/executable_df-agent-doctor"
}

@test "Entire is repository-scoped and privacy-preserving" {
    jq -e '.enabled == true' "$REPO/.entire/settings.json"
    jq -e '.telemetry == false' "$REPO/.entire/settings.json"
    jq -e '.strategy_options.push_sessions == false' "$REPO/.entire/settings.json"
    [[ -f "$REPO/.codex/hooks.json" ]]
    [[ -f "$REPO/.opencode/plugins/entire.ts" ]]
    [[ -f "$REPO/.pi/extensions/entire/index.ts" ]]
}

@test "cass indexes semantic vectors with bounded periodic refreshes" {
    grep -q 'index --full --semantic --build-hnsw' "$REPO/install/memory.sh"
    grep -q 'index --semantic --build-hnsw' "$REPO/install/memory.sh"
    ! grep -Eq '"\$_cass" watch|"\$ARCH_BIN/cass" watch' "$REPO/install/memory.sh"

    plist="$REPO/home/Library/LaunchAgents/dev.cade.cass-watch.plist.tmpl"
    grep -q '<string>index</string>' "$plist"
    ! grep -q '<string>--watch</string>' "$plist"
    ! grep -q '<string>--semantic</string>' "$plist"
    grep -q '<key>StartInterval</key>' "$plist"
    grep -q '<integer>300</integer>' "$plist"
    semantic="$REPO/home/Library/LaunchAgents/dev.cade.cass-semantic.plist.tmpl"
    grep -q '<string>--semantic</string>' "$semantic"
    grep -q '<string>--build-hnsw</string>' "$semantic"
    grep -q '<key>StartCalendarInterval</key>' "$semantic"
    grep -q '<key>CASS_SEMANTIC_EMBEDDER</key>' "$semantic"
    grep -q '<string>minilm</string>' "$semantic"
    grep -q '<key>CASS_INDEX_STALL_ABORT_SECS</key>' "$semantic"
    grep -q 'CASS_INDEX_STALL_ABORT_SECS.*0' "$REPO/install/memory.sh"
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
