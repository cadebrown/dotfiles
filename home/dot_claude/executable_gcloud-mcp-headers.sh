#!/usr/bin/env bash
# ~/.claude/gcloud-mcp-headers.sh — dynamic MCP headers for Google's official
# remote Cloud MCP servers (run, cloudresourcemanager, storage, bigquery —
# all *.googleapis.com/mcp). Workspace uses the community workspace-mcp stdio
# server instead (own OAuth client via ~/.google.env), not this helper.
#
# Claude Code runs this at connection time (headersHelper in ~/.claude.json,
# registered by install/claude.sh); stdout must be a JSON object of header
# name → value. Google's MCP servers authenticate with Application Default
# Credentials, so we mint a short-lived OAuth access token and pass it as a
# bearer, plus the quota/billing project Google requires for user creds.
#
# Auth source: a single `gcloud auth application-default login` (run once via
# `bash ~/dotfiles/install/auth.sh google`) writes the ADC refresh token to
# ~/.config/gcloud/application_default_credentials.json. `print-access-token`
# exchanges it for a fresh ~1h access token on each call — nothing long-lived
# is stored in any MCP config, and rotation heals itself.
#
# Project resolution (for x-goog-user-project), in order:
#   1. $GOOGLE_CLOUD_PROJECT (export it to pin a project per shell/fleet)
#   2. the ADC quota project set by `gcloud auth application-default
#      set-quota-project` (auth.sh does this at login)
#   3. `gcloud config get-value project`
#
# CAVEAT: the access token lasts ~1h and the helper runs at *connect* time, so
# an MCP session held open longer needs a `/mcp` reconnect to re-mint. That's
# the cost of short-lived creds (the secure default).
#
# On any failure emit an empty object: the server then responds 401 instead of
# the connection hard-failing.
set -uo pipefail

command -v gcloud >/dev/null 2>&1 || { printf '{}'; exit 0; }

token="$(gcloud auth application-default print-access-token 2>/dev/null || true)"
[[ -n "$token" ]] || { printf '{}'; exit 0; }

project="${GOOGLE_CLOUD_PROJECT:-}"
if [[ -z "$project" ]]; then
    project="$(gcloud config get-value billing/quota_project 2>/dev/null || true)"
    [[ "$project" == "(unset)" ]] && project=""
fi
if [[ -z "$project" ]]; then
    project="$(gcloud config get-value project 2>/dev/null || true)"
    [[ "$project" == "(unset)" ]] && project=""
fi

if [[ -n "$project" ]]; then
    printf '{"Authorization": "Bearer %s", "x-goog-user-project": "%s"}' "$token" "$project"
else
    # No quota project resolvable — emit just the bearer. Workspace/most Cloud
    # MCP calls still work; some Cloud APIs will 403 "user project required".
    printf '{"Authorization": "Bearer %s"}' "$token"
fi
