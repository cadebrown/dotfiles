# tests/lib-mcp-fixture.sh — shared fixture environment for the MCP emitter
# tests and the golden-capture script. Source AFTER the script under test
# (each install script re-sources _lib.sh, which resets DF_PACKAGES and
# re-sources the real ~/.*.env files — this function re-pins everything).

mcp_fixture_env() {
    local _tests_dir
    _tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Point the parser at the fixture list, with no overlays.
    DF_PACKAGES="$_tests_dir/fixtures/mcp"
    DF_OVERLAYS=()

    # Deterministic fake HOME so emitters that write files or probe
    # ~/.<svc>.env see a controlled world.
    _MCP_FIXTURE_HOME="${_MCP_FIXTURE_HOME:-$(mktemp -d)}"
    export HOME="$_MCP_FIXTURE_HOME"
    touch "$HOME/.context7.env" "$HOME/.tavily.env" "$HOME/.exa.env"

    # Deterministic credentials (override anything the real env sourced).
    export GITHUB_TOKEN="ghp_fixture_token_0000000000"
    export CONTEXT7_API_KEY="c7-fixture-key"
    export TAVILY_API_KEY="tav-fixture-key"
    export EXA_API_KEY="exa-fixture-key"
    export FIXTURE_KEY="fixture-url-key"
    unset FIXTURE_MISSING 2>/dev/null || true
}
