#!/usr/bin/env bash
# install/opencode.sh - opencode setup: verify binary + create Ollama fallback aliases
#
# Primary backend for opencode is MLX (mlx-openai-server, started via `mlxserve`),
# configured in home/dot_config/opencode/opencode.json.tmpl. This script handles
# the *fallback* path: context-boosted Ollama model aliases for when MLX isn't
# running or the user wants to compare backends.
#
# Ollama's default num_ctx (4096) is too small for agentic tool-use loops — the
# system prompt + tool schemas + conversation fill the window immediately. The
# aliases below clone each source model with a larger num_ctx.
#
# Context choices (tuned for M3 Max 128GB unified memory; Metal sees all RAM):
#   qwen3-coder:30b  → 256K (18GB weights + 60GB KV = 78GB; native 256K window)
#   qwen2.5-coder:7b → 128K (5GB weights  + 15GB KV = 20GB)
#   gpt-oss:20b      → 128K (13GB weights + 26GB KV = 39GB)
#   llama3.3:70b     → 128K (40GB weights + 43GB KV = 83GB; native 128K)
#   gpt-oss:120b     → skip (confirmed Ollama hang with large num_ctx; known bug)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "OpenCode (binary check + Ollama fallback aliases)"

if ! has opencode; then
    log_warn "opencode not found — skipping (run: brew install opencode)"
    exit 0
fi
log_okay "opencode: $(opencode --version 2>/dev/null | head -1)"

# MLX is the primary backend (config in opencode.json points at :8080).
# Ollama aliases below are a fallback — skip cleanly if Ollama isn't around.
if ! has ollama; then
    log_okay "ollama not installed — MLX-only setup, skipping fallback aliases"
    exit 0
fi
if ! ollama list &>/dev/null 2>&1; then
    log_okay "ollama server not running — skipping fallback alias creation"
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
