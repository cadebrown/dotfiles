# Local AI coding

Local LLM inference on macOS Apple Silicon (M-series) — no API keys, no rate
limits, no cloud — used as the default backend for **opencode** and **pi**
(and as a generic OpenAI-compatible endpoint for anything else).

## Overview

| Layer | Tool | Where it lives |
|---|---|---|
| **Server** | `mlxserve` (mlx-openai-server) | LaunchAgent `dev.cade.mlxserve` (KeepAlive) or foreground shell function; port 8080, OpenAI-compat + tool calling |
| **Server (fallback)** | Ollama | LaunchAgent, port 11434, OpenAI-compat |
| **Client** | opencode, pi | Both point at `localhost:8080/v1` by default on macOS |
| **Cloud** | Anthropic, OpenAI | Available everywhere via `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` |

MLX is the **primary backend** because it's roughly 2-3× faster than Ollama
(llama.cpp) on the M3 Max for the same quants, and `mlx-openai-server` adds
OpenAI tool-call parsing on top — which `mlx_lm.server` upstream still lacks.
Ollama remains installed as a plain fallback.

## Quick start

```sh
# LaunchAgent (preferred — survives terminal close, KeepAlive):
mlxstart                          # launchctl bootstrap dev.cade.mlxserve
mlxstatus                         # is it running?
mlxstop

# Or foreground in a terminal:
mlxserve                          # default: Qwen3.6-27B 8-bit (served as "qwen3.6-27b")
mlxserve qwen3.6-35b-a3b          # MoE alternative — fast tokens (3B active)
mlxserve coder-next               # Qwen3-Coder-Next 80B/3B MoE (no thinking)

# Then launch any client:
opencode                          # TUI agent, full tool-calling loop
pi                                # TUI agent, full tool-calling loop
```

All requests use the served-model-name `qwen3.6-27b` regardless of which
physical model is loaded — client configs stay stable when you swap models.

## `mlxserve` and `mlx-openai-server`

`mlxserve` is a shell function (defined in both `.zshrc` and `.bashrc`) that
starts `mlx-openai-server` with the right parsers for the chosen model:

```sh
mlx-openai-server launch \
    --model-type lm \
    --model-path unsloth/Qwen3.6-27B-MLX-8bit \
    --served-model-name qwen3.6-27b \
    --tool-call-parser qwen3_coder \
    --enable-auto-tool-choice \
    --reasoning-parser qwen3_5 \
    --kv-bits 8 --kv-group-size 64 \
    --host 127.0.0.1 --port 8080
```

The parser flags are critical: opencode and pi are tool-call-heavy, and the
upstream `mlx_lm.server` does not emit `tool_calls[]` in OpenAI format
([ml-explore/mlx-lm#1096](https://github.com/ml-explore/mlx-lm/issues/1096)).
`mlx-openai-server` adds parser layers that translate model output into the
standard format. Qwen3.6 emits Qwen3-Coder's XML tool-call wire format, so
the tool parser is `qwen3_coder` even on non-Coder variants; the reasoning
parser (`qwen3_5`) strips `<think>` blocks before clients see the output.

Override the port with `MLX_PORT=9000 mlxserve`.

## Pre-pulled models

Models live in `packages/mlx-models.txt`:

```
unsloth/Qwen3.6-27B-MLX-8bit         # primary (~35 GB, 256K ctx, reasoning-tuned)
# mlx-community/Qwen3.6-35B-A3B-8bit # MoE alternative — pull on demand
# mlx-community/Qwen3-Coder-Next-8bit# max tool-call throughput (~85 GB)
```

Pre-pull the default set in one shot:

```sh
bash ~/dotfiles/install/local-llm.sh pull-models
```

This is opt-in (the default `local-llm.sh` run only verifies binaries —
pulling ~35 GB of models on every bootstrap would be unfriendly). The
commented entries are one `mlxpull <alias>` away.

`HF_HOME` is set by `.zprofile` to `$_LOCAL_PLAT/.cache/huggingface`, so
weights live on scratch when scratch is configured.

## Per-tool config

Both coding agents are configured to use `localhost:8080/v1` as their
default backend on macOS. Each one lives under chezmoi:

| Tool | Default config | AGENTS file |
|---|---|---|
| **opencode** | `~/.config/opencode/opencode.json` (+ `plugin/git-context.ts`) | `~/.config/opencode/AGENTS.md` |
| **pi** | `~/.pi/agent/{settings,models}.json` (+ `themes/dotfiles.json`) | `~/.pi/agent/AGENTS.md` |

Both AGENTS files (plus Claude's `CLAUDE.md` and Codex's `AGENTS.md`)
include a shared partial — see [Agent guidance](agents.md). Cloud model pins
are single-sourced in `home/.chezmoidata.toml` (`{{ .models.opus }}` etc.).

### Switching to cloud

```sh
# opencode — switch agent or model in the TUI
/agent plan                     # plan agent runs Fable
/model anthropic/claude-sonnet-5

# pi — Ctrl+L (or /model)
/model anthropic/claude-sonnet-5
```

API keys come from `~/.<service>.env` files (written by `bash auth.sh`),
sourced into the shell by `~/.zprofile`.

## Ollama (fallback)

Installed via Homebrew (`brew "ollama"`). Managed as a LaunchAgent on macOS
— starts at login at `http://127.0.0.1:11434`. No model fleet is maintained
for it; an ad-hoc pull (`ollama pull qwen3-coder:30b`) is one command away.
(The old context-boosted alias machinery was removed — nothing consumed it.)

## run_onchange hooks

| Trigger file | Script re-run |
|---|---|
| `packages/pip.txt` | `install/local-llm.sh` (verifies binaries) |
| `home/dot_config/opencode/opencode.json.tmpl` | `install/opencode.sh` (binary check) |

`chezmoi update` after pulling dotfile changes re-verifies the setup.
