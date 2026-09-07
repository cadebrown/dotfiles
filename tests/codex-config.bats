#!/usr/bin/env bats

@test "Codex sync preserves Desktop integrations and activates domain tools" {
    local repo="${REPO:-$HOME/dotfiles}"
    run uv run --quiet --with tomlkit==0.13.3 \
        "$repo/tests/codex_config_test.py"
    [ "$status" -eq 0 ]
}

@test "Codex recognizes an installed remote plugin absent from local marketplace roots" {
    local repo="${REPO:-$HOME/dotfiles}"
    run env REPO="$repo" bash -c '
        source "$REPO/install/codex.sh"
        _declared_plugins() { printf "%s\n" "figma@openai-curated-remote"; }
        _marketplace_names() { printf "%s\n" "openai-curated"; }
        codex() {
            [[ "$*" == "plugin list --marketplace openai-curated-remote --available --json" ]] || return 1
            printf "%s\n" '\''{"installed":[{"pluginId":"figma@openai-curated-remote","marketplaceName":"openai-curated-remote","enabled":true}],"available":[]}'\''
        }
        _sync_plugins
        _check_plugins
    '
    [ "$status" -eq 0 ]
}

@test "Codex still rejects disabled remote plugins" {
    local repo="${REPO:-$HOME/dotfiles}"
    run env REPO="$repo" bash -c '
        source "$REPO/install/codex.sh"
        _declared_plugins() { printf "%s\n" "figma@openai-curated-remote"; }
        _marketplace_names() { printf "%s\n" "openai-curated"; }
        codex() {
            [[ "$*" == "plugin list --marketplace openai-curated-remote --available --json" ]] || return 1
            printf "%s\n" '\''{"installed":[{"pluginId":"figma@openai-curated-remote","marketplaceName":"openai-curated-remote","enabled":false}],"available":[]}'\''
        }
        _check_plugins
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing or disabled Codex plugin: figma@openai-curated-remote"* ]]
}
