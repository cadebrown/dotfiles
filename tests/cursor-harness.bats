#!/usr/bin/env bats
# Cursor instruction, CLI-merge, and worker contracts. Do not start the worker.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "Cursor CLI config is a write-once seed plus installer merge" {
    [[ -f "$REPO_ROOT/home/dot_cursor/create_cli-config.json" ]]
    [[ ! -e "$REPO_ROOT/home/dot_cursor/cli-config.json" ]]
    jq -e '.permissions.allow | index("Shell(*)")' \
        "$REPO_ROOT/home/dot_cursor/create_cli-config.json"
    jq -e '.exploreSubagentModel == "composer-2.5"' \
        "$REPO_ROOT/home/dot_cursor/create_cli-config.json"
    jq -e 'has("selectedModel") | not' \
        "$REPO_ROOT/home/dot_cursor/create_cli-config.json"
    grep -q '_sync_cursor_cli_config' "$REPO_ROOT/install/cursor.sh"
    grep -q 'exploreSubagentModel = "composer-2.5"' "$REPO_ROOT/install/cursor.sh"
    grep -q 'sync-cli' "$REPO_ROOT/install/cursor.sh"
}

@test "Cursor CLI merge preserves parent model and pins Explore to Composer 2.5" {
    local home="$BATS_TEST_TMPDIR/cli-home"
    mkdir -p "$home/.cursor"
    cat > "$home/.cursor/cli-config.json" <<'EOF'
{
  "permissions": { "allow": ["Read(*)"], "deny": [] },
  "sandbox": "enabled",
  "model": { "modelId": "keep-me", "displayModelId": "keep-me", "extra": true },
  "selectedModel": { "modelId": "keep-me", "parameters": [{"id": "effort", "value": "high"}] },
  "hasChangedDefaultModel": false,
  "attribution": { "keep": true },
  "authInfo": { "token": "runtime-only" }
}
EOF
    run env HOME="$home" DF_USE_PLAT=0 bash -c '
        source "$1/install/cursor.sh"
        _sync_cursor_cli_config >/dev/null
        jq -e ".permissions.allow | index(\"Read(*)\")" "$HOME/.cursor/cli-config.json"
        jq -e ".permissions.allow | index(\"Shell(*)\")" "$HOME/.cursor/cli-config.json"
        jq -e ".exploreSubagentModel == \"composer-2.5\"" "$HOME/.cursor/cli-config.json"
        jq -e ".selectedModel.modelId == \"keep-me\"" "$HOME/.cursor/cli-config.json"
        jq -e ".model.modelId == \"keep-me\"" "$HOME/.cursor/cli-config.json"
        jq -e ".model.extra == true" "$HOME/.cursor/cli-config.json"
        jq -e ".hasChangedDefaultModel == false" "$HOME/.cursor/cli-config.json"
        jq -e ".sandbox == \"enabled\"" "$HOME/.cursor/cli-config.json"
        jq -e ".attribution.keep == true" "$HOME/.cursor/cli-config.json"
        jq -e ".authInfo.token == \"runtime-only\"" "$HOME/.cursor/cli-config.json"
    ' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "Cursor CLI merge pins Explore without inventing a parent model" {
    local home="$BATS_TEST_TMPDIR/cli-null"
    mkdir -p "$home/.cursor"
    cat > "$home/.cursor/cli-config.json" <<'EOF'
{
  "permissions": { "allow": ["Shell(ls)"], "deny": [] },
  "model": null,
  "selectedModel": null,
  "hasChangedDefaultModel": false,
  "exploreSubagentModel": "default",
  "sandbox": "disabled",
  "authInfo": { "token": "runtime-only" }
}
EOF
    run env HOME="$home" DF_USE_PLAT=0 bash -c '
        source "$1/install/cursor.sh"
        _sync_cursor_cli_config >/dev/null
        jq -e ".permissions.allow | index(\"Shell(ls)\")" "$HOME/.cursor/cli-config.json"
        jq -e ".permissions.allow | index(\"Shell(*)\")" "$HOME/.cursor/cli-config.json"
        jq -e ".selectedModel == null" "$HOME/.cursor/cli-config.json"
        jq -e ".model == null" "$HOME/.cursor/cli-config.json"
        jq -e ".hasChangedDefaultModel == false" "$HOME/.cursor/cli-config.json"
        jq -e ".exploreSubagentModel == \"composer-2.5\"" "$HOME/.cursor/cli-config.json"
        jq -e ".sandbox == \"disabled\"" "$HOME/.cursor/cli-config.json"
        jq -e ".authInfo.token == \"runtime-only\"" "$HOME/.cursor/cli-config.json"
    ' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "df-cursor-worker requests computer use with no idle release" {
    local worker="$REPO_ROOT/home/dot_local/bin/executable_df-cursor-worker"
    grep -q -- '--wait' "$worker"
    grep -q -- '--computer-use' "$worker"
    grep -q -- '--idle-release-timeout 0' "$worker"
    grep -q 'DF_CURSOR_WORKER_NAME' "$worker"
    grep -q 'DF_CURSOR_WORKER_DIRS' "$worker"
    grep -q -- '--worker-dir' "$worker"
    grep -q 'exec agent' "$worker"
    ! grep -q 'agent worker start' "$worker"
}

@test "Cursor worker LaunchAgent is NFS-safe and persistent" {
    local plist="$REPO_ROOT/home/Library/LaunchAgents/dev.cade.cursor-worker.plist.tmpl"
    grep -q 'exec df-cursor-worker' "$plist"
    grep -q 'LimitLoadToSessionType' "$plist"
    grep -q 'Aqua' "$plist"
    grep -q 'KeepAlive' "$plist"
    grep -q 'SuccessfulExit' "$plist"
    grep -q -- '--wait' "$REPO_ROOT/home/dot_local/bin/executable_df-cursor-worker"
    ! grep -qi 'hostname' "$plist"
    grep -q 'DF_CURSOR_WORKER' "$REPO_ROOT/install/cursor.sh"
    grep -q '_ensure_cursor_worker' "$REPO_ROOT/install/cursor.sh"
    grep -q 'co.anysphere.cursor-computer-use' "$REPO_ROOT/install/cursor.sh"
}

@test "Cursor worker wrapper records argv without starting a worker" {
    local fake_bin="$BATS_TEST_TMPDIR/bin"
    local home="$BATS_TEST_TMPDIR/worker-home"
    mkdir -p "$fake_bin" "$home/dotfiles" "$home/extra"
    cat > "$fake_bin/agent" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$HOME/agent-args"
exit 0
EOF
    chmod +x "$fake_bin/agent"
    run env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
        DF_CURSOR_WORKER_NAME=testhost \
        DF_CURSOR_WORKER_DIRS="$home/extra" \
        bash "$REPO_ROOT/home/dot_local/bin/executable_df-cursor-worker"
    [ "$status" -eq 0 ]
    grep -q -- '--computer-use' "$home/agent-args"
    grep -q -- '--wait' "$home/agent-args"
    grep -q -- '--idle-release-timeout 0' "$home/agent-args"
    grep -q -- '--name testhost' "$home/agent-args"
    grep -q -- "--worker-dir $home/dotfiles" "$home/agent-args"
    grep -q -- "--worker-dir $home/extra" "$home/agent-args"
    grep -Eq '(^|[[:space:]])start$' "$home/agent-args"
}
