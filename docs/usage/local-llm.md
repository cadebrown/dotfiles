# Local AI coding

Local LLM inference on macOS Apple Silicon (M-series) — no API keys, no rate
limits, no cloud — used as the default backend for **aider**, **opencode**,
and **pi**.

## Overview

| Layer | Tool | Where it lives |
|---|---|---|
| **Server** | `mlxserve` (mlx-openai-server) | Foreground process, port 8080, OpenAI-compat + tool calling |
| **Server (fallback)** | Ollama | LaunchAgent, port 11434, OpenAI-compat |
| **Client** | aider, opencode, pi | All point at `localhost:8080/v1` by default on macOS |
| **Cloud** | Anthropic, OpenAI | Available everywhere via `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` |

MLX is the **primary backend** because it's roughly 2-3× faster than Ollama
(llama.cpp) on the M3 Max for the same 4-bit quants, and `mlx-openai-server`
adds OpenAI tool-call parsing on top — which `mlx_lm.server` upstream still
lacks. Ollama remains installed as a fallback for backend comparison and for
non-Apple-Silicon users.

## Quick start

```sh
# Start the local server (one terminal — leave it running)
mlxserve                          # default: Qwen3-Coder-30B-A3B (256K ctx)

# Then in another terminal, launch any of:
aider                             # CLI, whole-format edits
opencode                          # TUI agent, full tool-calling loop
pi                                # TUI agent, full tool-calling loop

# Switch model in the running server
mlxserve qwen2.5-coder:7b         # smaller/faster
mlxserve gpt-oss:20b              # reasoning
```

## `mlxserve` and `mlx-openai-server`

`mlxserve` is a shell function (defined in both `.zshrc` and `.bashrc`) that
starts `mlx-openai-server` with the right tool-call parser for the chosen
model:

```sh
mlx-openai-server launch \
    --model-type lm \
    --model-path mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit \
    --tool-call-parser qwen3_coder \
    --enable-auto-tool-choice \
    --host 127.0.0.1 \
    --port 8080
```

The parser flag is critical: opencode and pi are tool-call-heavy, and the
upstream `mlx_lm.server` does not emit `tool_calls[]` in OpenAI format
([ml-explore/mlx-lm#1096](https://github.com/ml-explore/mlx-lm/issues/1096)).
`mlx-openai-server` adds parser layers (`qwen3_coder`, `harmony`, etc.) that
translate model output into the standard format.

Override the port with `MLX_PORT=9000 mlxserve`.

## Pre-pulled models

Models live in `packages/mlx-models.txt`:

```
mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit   # primary (~25 GB, 256K ctx)
mlx-community/Qwen2.5-Coder-7B-Instruct-4bit      # fast fallback (~4 GB)
mlx-community/gpt-oss-20b-MLX-4bit                # reasoning (~12 GB)
```

Pre-pull all of them in one shot:

```sh
bash ~/dotfiles/install/local-llm.sh pull-models
```

This is opt-in (the default `local-llm.sh` run only verifies binaries —
pulling ~40 GB of models on every bootstrap would be unfriendly).

`HF_HOME` is set by `.zprofile` to `$_LOCAL_PLAT/.cache/huggingface`, so
weights live on scratch when scratch is configured.

## Per-tool config

All three coding agents are configured to use `localhost:8080/v1` as their
default backend on macOS. Each one lives under chezmoi:

| Tool | Default config | AGENTS / conventions |
|---|---|---|
| **aider** | `~/.aider.conf.yml`, `~/.aider.model.settings.yml`, `~/.aider.model.metadata.json` | `~/.config/aider/CONVENTIONS.md` |
| **opencode** | `~/.config/opencode/opencode.json` (+ `plugin/git-context.ts`) | `~/.config/opencode/AGENTS.md` |
| **pi** | `~/.pi/agent/{settings,models}.json` (+ `themes/dotfiles.json`) | `~/.pi/agent/AGENTS.md` |

All three AGENTS/CONVENTIONS files (plus Claude's `CLAUDE.md` and Codex's
`AGENTS.md`) include a shared partial — see [Agent guidance](agents.md).

### Switching to cloud

All three tools have cloud aliases preconfigured:

```sh
# aider
aider --model sonnet            # claude-sonnet-4-6
aider --model opus              # claude-opus-4-7
aider --model gpt5              # gpt-5

# opencode — switch agent or model in the TUI
/agent plan                     # plan agent runs Opus
/model anthropic/claude-sonnet-4-6

# pi — Ctrl+L (or /model)
/model anthropic/claude-sonnet-4-6
```

API keys come from `~/.<service>.env` files (written by `bash auth.sh`),
sourced into the shell by `~/.zprofile`.

## Ollama (fallback)

Installed via Homebrew (`brew "ollama"`). Managed as a LaunchAgent on macOS
— starts at login at `http://127.0.0.1:11434`.

`install/opencode.sh` creates context-boosted Ollama model aliases for
backend comparison:

| Alias | Base | Context |
|---|---|---|
| `qwen3-coder:30b-ctx256k` | `qwen3-coder:30b` | 256K |
| `llama3.3:70b-ctx128k` | `llama3.3:70b` | 128K |
| `gpt-oss:20b-ctx128k` | `gpt-oss:20b` | 128K |
| `qwen2.5-coder:7b-ctx128k` | `qwen2.5-coder:7b` | 128K |

`gpt-oss:120b` is excluded — confirmed Ollama hang bug with large `num_ctx`.

## run_onchange hooks

| Trigger file | Script re-run |
|---|---|
| `packages/pip.txt` | `install/local-llm.sh` (verifies binaries) |
| `home/dot_config/opencode/opencode.json.tmpl` | `install/opencode.sh` (Ollama fallback aliases) |

`chezmoi update` after pulling dotfile changes re-verifies the setup.
