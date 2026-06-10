#!/usr/bin/env bash
# install/local-llm.sh - set up local LLM data directories, verify tools, optionally pull models
#
# MLX is the primary local-inference path on Apple Silicon (2-3x faster than
# Ollama via llama.cpp on M3 Max). Ollama stays as a fallback.
#
# Binary installs handled upstream:
#   ollama    -> packages/Brewfile  (install/homebrew.sh, step 4)
#   mlx-lm    -> packages/pip.txt   (install/python.sh,   step 6)
#
# Modes:
#   default       -> dirs + binary checks (idempotent, fast)
#   pull-models   -> additionally pre-pull MLX models in packages/mlx-models.txt
#                    (large download — ~35GB for the default set)
#
# Manual pulls if you want a specific model:
#   ollama pull qwen3-coder:30b
#   mlx_lm.generate --model unsloth/Qwen3.6-27B-MLX-8bit \
#       --prompt "x" --max-tokens 1   # downloads + warms cache
#
# Run the MLX server (from your shell):
#   mlxserve [model]    # see home/dot_zshrc.tmpl for the shell function
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_mode="${1:-check}"

log_section "Local LLM tooling ($_mode)"

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

if has mlx-openai-server; then
    log_okay "mlx-openai-server: present (tool-calling MLX server)"
else
    log_warn "mlx-openai-server not found — run: uv tool install mlx-openai-server"
    (( _missing++ )) || true
fi

[[ "$_missing" -gt 0 ]] && log_warn "$_missing tool(s) missing — re-run after step 4/6 completes"

### MLX model pre-pull (opt-in via `pull-models` arg) ###
if [[ "$_mode" == "pull-models" ]]; then
    log_section "MLX model pull (from packages/mlx-models.txt)"
    if ! has mlx_lm.generate; then
        die "mlx_lm.generate not found — install mlx-lm first (uv tool install mlx-lm)"
    fi
    _models_file="$DF_PACKAGES/mlx-models.txt"
    [[ -r "$_models_file" ]] || die "missing $_models_file"

    while IFS= read -r _model; do
        # skip comments + blanks
        _model="${_model%%#*}"
        _model="${_model#"${_model%%[![:space:]]*}"}"
        _model="${_model%"${_model##*[![:space:]]}"}"
        [[ -z "$_model" ]] && continue

        # HF cache layout: hub/models--<org>--<repo>/. Slash → "--" in dir name.
        _slash_repl="${_model//\//--}"
        if compgen -G "$HOME/.cache/huggingface/hub/models--${_slash_repl}*" >/dev/null 2>&1 \
           || compgen -G "${LOCAL_PLAT}/.cache/huggingface/hub/models--${_slash_repl}*" >/dev/null 2>&1; then
            log_okay "already cached: $_model"
            continue
        fi

        log_info "pulling $_model (this may take a while...)"
        if mlx_lm.generate --model "$_model" --prompt "x" --max-tokens 1 >/dev/null 2>&1; then
            log_okay "pulled $_model"
        else
            log_warn "pull failed for $_model — check name / network"
        fi
    done < "$_models_file"
fi

log_okay "Local LLM tooling ready"
