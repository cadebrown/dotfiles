#!/usr/bin/env bash
# install/opencode.sh - configure OpenCode with context-boosted Ollama model aliases
#
# Ollama's default num_ctx (4096) is too small for agentic tool-use loops —
# the system prompt + tool schemas + conversation fill the window immediately.
# This script creates aliased model entries with larger context windows.
#
# Context choices (tuned for M3 Max 128GB unified memory):
# Apple Silicon unified memory means no CPU/GPU split — Metal accesses all 128GB.
# KV cache cost at 128K: ~30GB (qwen3-coder:30b), ~43GB (70b), ~26GB (20b), ~15GB (7b)
# All fit comfortably; 128K is the right default here, not the 32K NVIDIA sweet spot.
#
#   qwen3-coder:30b  → 256K (18GB weights + 60GB KV = 78GB; trained on 256K — use full window)
#   qwen2.5-coder:7b → 128K (5GB weights  + 15GB KV = 20GB)
#   gpt-oss:20b      → 128K (13GB weights + 26GB KV = 39GB)
#   llama3.3:70b     → 128K (40GB weights + 43GB KV = 83GB; trained on 128K)
#   gpt-oss:120b     → skip (confirmed Ollama hang with large num_ctx; known bug)
#
# mlx-lm integration: mlx_lm.server tool calling is currently broken upstream
# (draft fix in PR #1027). Config will be added here once the fix lands.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "OpenCode (Ollama context windows)"

if ! has opencode; then
    log_warn "opencode not found — skipping (run: brew install opencode)"
    exit 0
fi
log_okay "opencode: $(opencode --version 2>/dev/null | head -1)"

if ! has ollama; then
    log_warn "ollama not found — skipping model context setup"
    exit 0
fi

# Ensure ollama server is reachable
if ! ollama list &>/dev/null 2>&1; then
    log_warn "ollama server not responding — skipping model context setup"
    exit 0
fi

# Format: "source_model|alias|num_ctx"
# Omit gpt-oss:120b — large num_ctx causes confirmed hangs in Ollama.
_MODELS=(
    "qwen3-coder:30b|qwen3-coder:30b-ctx256k|262144"
    "qwen2.5-coder:7b|qwen2.5-coder:7b-ctx128k|131072"
    "gpt-oss:20b|gpt-oss:20b-ctx128k|131072"
    "llama3.3:70b|llama3.3:70b-ctx128k|131072"
)

_created=0
_skipped=0
_failed=0

for _entry in "${_MODELS[@]}"; do
    IFS='|' read -r _src _alias _ctx <<< "$_entry"

    if ! ollama list 2>/dev/null | awk '{print $1}' | grep -qF "$_src"; then
        log_debug "Source not present, skipping: $_src"
        (( _skipped++ )) || true
        continue
    fi

    if ollama list 2>/dev/null | awk '{print $1}' | grep -qF "$_alias"; then
        log_debug "Already exists: $_alias"
        (( _skipped++ )) || true
        continue
    fi

    log_info "Creating $_alias (num_ctx=$_ctx)"
    _mf="$(mktemp)"
    printf 'FROM %s\nPARAMETER num_ctx %s\n' "$_src" "$_ctx" > "$_mf"
    if run_logged ollama create "$_alias" -f "$_mf"; then
        log_okay "Created: $_alias"
        (( _created++ )) || true
    else
        log_warn "Failed: $_alias"
        (( _failed++ )) || true
    fi
    rm -f "$_mf"
done

log_okay "Models: $_created created, $_skipped skipped, $_failed failed"
