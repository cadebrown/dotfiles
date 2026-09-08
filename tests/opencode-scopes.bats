#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    source "$REPO_ROOT/install/opencode.sh"
    export HOME="$BATS_TEST_TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_STATE_HOME="$HOME/.local/state"
    unset OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR
    DF_OVERLAYS=()
    mkdir -p "$HOME/.config/opencode"
}

catalog_config() {
    mcp_servers_each --all | jq -s '{permission:"allow", model:"fixture/selected",
        agent:{build:{model:"fixture/selected"}, review:{permission:{edit:"deny",bash:"deny"}}},
        mcp:(map({key:.name,value:{type:"remote",url:"https://example.invalid/mcp",enabled:false}}) | from_entries)}'
}

@test "OpenCode scopes every catalog capability and keeps core agents small" {
    catalog_config | _scope_opencode_mcp > "$HOME/scoped.json"
    jq -e '
        . as $c
        | ["context7_*","crates_*","openaiDeveloperDocs_*","qmd_*","rust-docs_*"] as $core
        | all(.mcp | keys[]; . as $n | $c.permission[$n+"_*"] == "deny")
        and all(["build","plan","review"][]; . as $a |
            ([$c.agent[$a].permission | to_entries[] | select(.value=="allow") | .key] | sort) == $core)
        and all($c.mcp | keys[]; . as $n |
            any($c.agent[]; .permission[$n+"_*"] == "allow"))
        and all(["research","browser","creative","desktop","cloud","workspace","math","repository"][];
            . as $a | $c.agent[$a].mode == "all" and ($c.agent[$a] | has("model") | not))
        and $c.agent.review.permission.edit == "deny"
        and $c.agent.review.permission.task == "deny"
        and $c.agent.review.permission.bash == "deny"
        and $c.permission["*"] == "allow"
        and $c.agent.repository.permission["github_*"] == "allow"
        and $c.agent.browser.permission["blender_*"] == "deny"
    ' "$HOME/scoped.json"
}

@test "OpenCode discovers custom namespaces without widening core or prefix matches" {
    printf '%s\n' '{"permission":"allow","mcp":{"qmd":{},"qmd_extra":{},"acme.search":{}}}' |
        _scope_opencode_mcp > "$HOME/scoped.json"
    run uv run --no-project python - "$HOME/scoped.json" <<'PY'
import fnmatch
import json
import sys

config = json.load(open(sys.argv[1]))
def action(agent, tool):
    rules = [*config["permission"].items(), *config["agent"][agent]["permission"].items()]
    return [value for pattern, value in rules if fnmatch.fnmatchcase(tool, pattern)][-1]
assert action("build", "qmd_search") == "allow"
assert action("build", "qmd_extra_search") == "deny"
assert action("mcp-qmd_extra", "qmd_search") == "deny"
assert action("mcp-qmd_extra", "qmd_extra_search") == "allow"
assert action("mcp-acme_search", "acme_search_query") == "allow"
assert action("build", "acme_search_query") == "deny"
assert "acme.search" in config["agent"]["mcp-acme_search"]["description"]
PY
    [ "$status" -eq 0 ]
}

@test "OpenCode sync preserves models effort custom agents and MCP activation idempotently" {
    cat > "$HOME/.config/opencode/opencode.json" <<'JSON'
{"model":"fixture/my-model","small_model":"fixture/small","default_agent":"build",
 "provider":{"fixture":{"options":{"baseURL":"http://localhost:4321/v1"}}},
 "permission":{"*":"allow","bash":{"git push*":"deny","*":"allow"}},
 "agent":{"build":{"model":"fixture/build","variant":"high","reasoningEffort":"high"},
 "review":{"model":"fixture/reviewer","permission":{"edit":"deny","bash":"deny"}},
 "custom-agent":{"model":"fixture/custom","prompt":"Preserve this","permission":{"edit":"ask"}}},
 "mcp":{"blender":{"type":"local","command":["old"],"enabled":false,"timeout":9123},
 "my-service":{"type":"local","command":["custom"],"enabled":false}}}
JSON
    chezmoi() { printf '%s\n' '{"model":"seed/default","agent":{"build":{"model":"seed/build"}}}'; }
    _sync_config >/dev/null
    jq -e '.model == "fixture/my-model" and .small_model == "fixture/small"
        and .agent.build.model == "fixture/build" and .agent.build.variant == "high"
        and .agent.build.reasoningEffort == "high" and .agent.review.model == "fixture/reviewer"
        and .provider.fixture.options.baseURL == "http://localhost:4321/v1"
        and .permission.bash["git push*"] == "deny"
        and .agent["custom-agent"].prompt == "Preserve this"
        and .agent["custom-agent"].permission.edit == "ask"
        and .mcp.blender.enabled == false and .mcp.blender.timeout == 9123
        and .mcp["my-service"].command == ["custom"] and .mcp["my-service"].enabled == false
        and .agent["mcp-my-service"].permission["my-service_*"] == "allow"
        and (.agent.creative | has("model") | not)' "$HOME/.config/opencode/opencode.json"
    cp "$HOME/.config/opencode/opencode.json" "$HOME/first.json"
    _sync_config >/dev/null
    cmp "$HOME/first.json" "$HOME/.config/opencode/opencode.json"
}

@test "OpenCode refuses ambiguous normalized namespaces before changing config" {
    printf '%s\n' '{"mcp":{"same.name":{},"same_name":{}}}' > "$HOME/.config/opencode/opencode.json"
    cp "$HOME/.config/opencode/opencode.json" "$HOME/original.json"
    chezmoi() { printf '{}\n'; }
    run _sync_config
    [ "$status" -ne 0 ]
    [[ "$output" == *"collide"* ]]
    cmp "$HOME/original.json" "$HOME/.config/opencode/opencode.json"
}

@test "native OpenCode resolves scoped permissions and inherited specialist models" {
    catalog_config | _scope_opencode_mcp > "$HOME/.config/opencode/opencode.json"
    run uv run --no-project python - <<'PY'
import fnmatch
import json
import subprocess

def native(*arguments):
    result = subprocess.run(["opencode", "debug", *arguments], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)
def action(agent, tool):
    return [rule["action"] for rule in agent["permission"] if fnmatch.fnmatchcase(tool, rule["permission"])][-1]
config = native("config")
assert config["model"] == "fixture/selected"
build = native("agent", "build")
browser = native("agent", "browser")
review = native("agent", "review")
assert action(build, "qmd_search") == "allow"
assert action(build, "chrome-devtools_take_screenshot") == "deny"
assert action(build, "github_create_issue") == "deny"
assert action(build, "bash") == "allow"
assert action(browser, "chrome-devtools_take_screenshot") == "allow"
assert action(browser, "google-workspace_send_gmail_message") == "deny"
assert browser["mode"] == "all" and "model" not in browser
assert action(review, "edit") == "deny" and action(review, "task") == "deny"
assert action(review, "bash") == "deny" and action(review, "blender_execute_blender_code") == "deny"
assert build["model"] == {"providerID":"fixture", "modelID":"selected"}
PY
    [ "$status" -eq 0 ]
}
