#!/usr/bin/env bash
# install/local-llm.sh - set up local LLM data directories and verify tools
#
# Creates PLAT-isolated directories for Ollama and HuggingFace model storage,
# then confirms that the expected binaries (from brew/python.sh) are present.
#
# Binary installs handled upstream:
#   ollama    -> packages/Brewfile  (install/homebrew.sh, step 4)
#   mlx-lm    -> packages/pip.txt   (install/python.sh,   step 6)
#   aider     -> packages/pip.txt   (install/python.sh,   step 6)
#
# To pull models manually after install:
#   ollama pull devstral
#   mlx_lm.generate --model mlx-community/Devstral-Small-2505-4bit  (downloads from HF Hub)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Local LLM tooling"

### Data directories ###
# HuggingFace weights (mlx-lm) go under LOCAL_PLAT (PLAT-isolated, avoids NFS).
# Ollama models stay at ~/.ollama/models — managed by the app/daemon, not redirected.

ensure_dir "$LOCAL_PLAT/.cache/huggingface"
log_okay "HF_HOME → $LOCAL_PLAT/.cache/huggingface"

### Binary checks ###
# Warn (not fail) — targeted runs may have skipped step 4 or 6.

_missing=0

if has ollama; then
    log_okay "ollama: $(ollama --version 2>/dev/null | head -1)"
else
    log_warn "ollama not found — run: brew install ollama  (or re-run install/homebrew.sh)"
    (( _missing++ )) || true
fi

if has mlx_lm.generate; then
    log_okay "mlx-lm: present"
else
    log_warn "mlx_lm.generate not found — run: uv tool install mlx-lm"
    (( _missing++ )) || true
fi

if has aider; then
    log_okay "aider: $(aider --version 2>/dev/null | head -1)"
else
    log_warn "aider not found — run: uv tool install aider-chat"
    (( _missing++ )) || true
fi

[[ "$_missing" -gt 0 ]] && log_warn "$_missing tool(s) missing — re-run after step 4/6 completes"

log_okay "Local LLM tooling ready"
