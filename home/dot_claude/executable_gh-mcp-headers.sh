#!/usr/bin/env bash
# ~/.claude/gh-mcp-headers.sh — dynamic MCP headers for the GitHub server.
#
# Claude Code runs this at connection time (headersHelper in ~/.claude.json,
# registered by install/claude.sh); stdout must be a JSON object of header
# name → value. The token comes from gh's credential store, so rotation via
# `gh auth login` / `gh auth refresh` heals itself — no stored token, no
# per-run reconciliation.
#
# On any failure emit an empty object: the server then responds 401 instead
# of the connection hard-failing.
set -uo pipefail

token="$(gh auth token 2>/dev/null)" || token=""
if [[ -z "$token" ]]; then
    printf '{}'
    exit 0
fi
printf '{"Authorization": "Bearer %s"}' "$token"
