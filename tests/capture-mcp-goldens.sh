#!/usr/bin/env bash
# tests/capture-mcp-goldens.sh — regenerate tests/golden/* from the CURRENT
# emitters. Run this ONLY when an output-shape change is intentional; commit
# the golden diff together with the emitter change so review sees both.
#
# tests/mcp-emitters.bats compares live emitter output against these files.
set -euo pipefail

_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(dirname "$_TESTS_DIR")"

# shellcheck source=lib-mcp-fixture.sh
source "$_TESTS_DIR/lib-mcp-fixture.sh"
mcp_fixture_env   # controlled HOME + credentials + DF_PACKAGES/DF_OVERLAYS

# --- opencode: the mcp JSON object ---
# shellcheck source=../install/opencode.sh
source "$_REPO_ROOT/install/opencode.sh"
mcp_fixture_env   # re-apply: sourcing the script re-sourced _lib.sh
_emit_opencode_mcp 2>/dev/null | jq -S . > "$_TESTS_DIR/golden/opencode-mcp.json"

# --- cursor: ~/.cursor/mcp.json ---
# shellcheck source=../install/cursor.sh
source "$_REPO_ROOT/install/cursor.sh"
mcp_fixture_env
_sync_cursor_mcp >/dev/null 2>&1
jq -S . "$HOME/.cursor/mcp.json" > "$_TESTS_DIR/golden/cursor-mcp.json"

# --- codex: the [mcp_servers.*] TOML blocks ---
# shellcheck source=../install/codex.sh
source "$_REPO_ROOT/install/codex.sh"
mcp_fixture_env
_codex_out="$(mktemp)"
_emit_mcp_blocks_to "$_codex_out" >/dev/null 2>&1
cp "$_codex_out" "$_TESTS_DIR/golden/codex-mcp.toml"
rm -f "$_codex_out"

echo "goldens regenerated under $_TESTS_DIR/golden/"
