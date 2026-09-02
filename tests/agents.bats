#!/usr/bin/env bats
# Static contracts for the agent harness. These catch upstream CLI drift before
# a bootstrap silently installs a degraded configuration.

setup() {
    REPO="${REPO:-$HOME/dotfiles}"
}

@test "agent installers and doctor have valid shell syntax" {
    bash -n "$REPO/install/memory.sh"
    bash -n "$REPO/install/skills-sync.sh"
    bash -n "$REPO/install/codex.sh"
    bash -n "$REPO/install/agent-tools.sh"
    bash -n "$REPO/home/dot_local/bin/executable_df-agent-doctor"
}

@test "agent declaration installers fail on incomplete reconciliation" {
    grep -Fq '(( _fail == 0 )) || die "Agent skill sync failed' \
        "$REPO/install/skills-sync.sh"
    grep -Fq '_check_registry 1 || die' "$REPO/install/skills-sync.sh"
    grep -Fq 'preserve  $_dir (locally modified since last install)' \
        "$REPO/install/skills-sync.sh"
    grep -Fq '(( _fail == 0 )) || die "Claude plugin installation failed' \
        "$REPO/install/claude.sh"
    grep -Fq '(( _fail == 0 )) || die "Claude MCP registration failed' \
        "$REPO/install/claude.sh"
    grep -Fq '{type: "stdio", command: $w[0], args: $w[1:]}' \
        "$REPO/install/claude.sh"
}

@test "agent doctor installer deploys and repairs the command in ARCH_BIN" {
    local fake_home="$BATS_TEST_TMPDIR/agent-tools-home"
    local destination

    run env HOME="$fake_home" DF_USE_PLAT=1 bash "$REPO/install/agent-tools.sh"
    [ "$status" -eq 0 ]
    destination="$(printf '%s\n' "$fake_home"/.local/plat_*/bin/df-agent-doctor)"
    [ -x "$destination" ]
    cmp -s "$REPO/home/dot_local/bin/executable_df-agent-doctor" "$destination"

    printf '#!/usr/bin/env bash\nexit 0\n' > "$destination"
    chmod 755 "$destination"
    run env HOME="$fake_home" DF_USE_PLAT=1 bash "$REPO/install/agent-tools.sh"
    [ "$status" -eq 0 ]
    cmp -s "$REPO/home/dot_local/bin/executable_df-agent-doctor" "$destination"
}

@test "bootstrap explicitly deploys agent helper commands" {
    grep -Fq 'bash "$DF_INSTALL_DIR/agent-tools.sh"' "$REPO/bootstrap.sh"
    grep -Fxq '.local/bin/df-agent-doctor' "$REPO/home/.chezmoiignore"
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

@test "zsh leaves tc to the system traffic-control command" {
    ! grep -Eq '^[[:space:]]*tc[[:space:]]*\(\)' "$REPO/home/dot_zshrc.tmpl"
}

@test "cass indexing is manual and semantic work is bounded" {
    grep -q 'models backfill.*--tier quality' "$REPO/install/memory.sh"
    grep -q 'index --full' "$REPO/install/memory.sh"
    ! grep -q 'index --semantic' "$REPO/install/memory.sh"
    ! grep -q 'nohup.*cass.*index' "$REPO/install/memory.sh"
    ! grep -q -- '--build-hnsw' "$REPO/install/memory.sh"
    [ ! -e "$REPO/home/Library/LaunchAgents/dev.cade.cass-watch.plist.tmpl" ]
    [ ! -e "$REPO/home/Library/LaunchAgents/dev.cade.cass-semantic.plist.tmpl" ]
    grep -q '^Library/LaunchAgents/dev\.cade\.cass-watch\.plist$' "$REPO/home/.chezmoiremove"
    grep -q '^Library/LaunchAgents/dev\.cade\.cass-semantic\.plist$' "$REPO/home/.chezmoiremove"
}

@test "memory setup fails closed when cass or qmd is unhealthy" {
    grep -q 'cass: installation did not produce a working command' "$REPO/install/memory.sh"
    grep -q 'cass: all-MiniLM-L6-v2 model is still unavailable' "$REPO/install/memory.sh"
    grep -q 'qmd not found.*run install/node.sh' "$REPO/install/memory.sh"
    grep -q 'qmd MCP daemon failed its health check' "$REPO/install/memory.sh"
    ! grep -q 'source build failed.*skipping' "$REPO/install/memory.sh"
    ! grep -q 'qmd embed failed.*degraded' "$REPO/install/memory.sh"
}

@test "qmd health wait does not depend on the non-macOS seq command" {
    fake_bin="$BATS_TEST_TMPDIR/bin"
    marker="$BATS_TEST_TMPDIR/attempts"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\nexit 127\n' > "$fake_bin/seq"
    chmod +x "$fake_bin/seq"

    run env PATH="$fake_bin:$PATH" QMD_TEST_MARKER="$marker" REPO="$REPO" bash -c '
        source "$REPO/install/_lib.sh"
        sleep() { :; }
        _qmd_daemon_healthy() {
            printf x >> "$QMD_TEST_MARKER"
            [[ "$(wc -c < "$QMD_TEST_MARKER")" -ge 3 ]]
        }
        _qmd_wait_healthy
        [[ "$(wc -c < "$QMD_TEST_MARKER")" -eq 3 ]]
    '
    [ "$status" -eq 0 ]
}

@test "qmd health check follows the localhost MCP endpoint" {
    run env REPO="$REPO" bash -c '
        source "$REPO/install/_lib.sh"
        curl() {
            [[ "${*: -1}" == "http://localhost:8181/health" ]] || return 1
            printf "{\"status\":\"ok\"}\n"
        }
        _qmd_daemon_healthy
    '
    [ "$status" -eq 0 ]
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
