#!/usr/bin/env bash
# install/opencode.sh - verify the opencode binary is present
#
# Primary backend for opencode is MLX (mlx-openai-server via the mlxserve
# LaunchAgent, KeepAlive on :8080), configured in
# home/dot_config/opencode/opencode.json.tmpl. Ollama stays installed as a
# plain fallback — an ad-hoc model is one command away (`ollama pull
# qwen3-coder:30b`) — but the old context-boosted alias fleet is gone:
# nothing consumed it and its model lineup aged out.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "OpenCode (binary check)"

if ! has opencode; then
    log_warn "opencode not found — skipping (run: brew install opencode)"
    exit 0
fi
log_okay "opencode: $(opencode --version 2>/dev/null | head -1)"
