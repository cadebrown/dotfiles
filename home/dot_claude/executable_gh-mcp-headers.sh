#!/usr/bin/env bash
# ~/.claude/gh-mcp-headers.sh — dynamic MCP headers for the GitHub server.
#
# Claude Code runs this at connection time (headersHelper in ~/.claude.json,
# registered by install/claude.sh); stdout must be a JSON object of header
# name → value.
#
# Token source, in order:
#   1. $GITHUB_TOKEN — the PAT in ~/.github.env. This is the single source of
#      truth: one value, sourced into every shell, shared across the NFS fleet.
#   2. `gh auth token` (keyring) — fallback for a machine you'd rather log in
#      on interactively instead of carrying the PAT.
# Note gh itself returns $GITHUB_TOKEN ahead of its keyring when the env var is
# set (cli/cli#8347), so reading the env var directly here is both explicit and
# matches gh's own precedence — it just removes the indirection that let a stale
# env token silently shadow a fresh `gh auth login`.
#
# Rotating the PAT in ~/.github.env (or `gh auth login`) is all it takes — no
# token is stored in any MCP config. If the GitHub MCP starts returning 401,
# the token is almost certainly expired: run `bash ~/dotfiles/install/auth.sh
# status` to confirm liveness, then update ~/.github.env.
#
# On any failure emit an empty object: the server then responds 401 instead of
# the connection hard-failing.
set -uo pipefail

token="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
if [[ -z "$token" ]]; then
    printf '{}'
    exit 0
fi
printf '{"Authorization": "Bearer %s"}' "$token"
