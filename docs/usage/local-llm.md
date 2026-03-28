# Local AI coding

Local LLM inference on macOS Apple Silicon (M-series) — no API keys, no rate limits, no cloud.

## Overview

Two inference backends, one coding agent layer:

| Tool | Format | Server | When to use |
|---|---|---|---|
| **Ollama** | GGUF | `localhost:11434/v1` (OpenAI-compatible) | Primary backend — always-on LaunchAgent, large models, multi-client |
| **mlx-lm** | MLX | `localhost:8080/v1` (OpenAI-compatible) | On-demand — faster on Apple Silicon Metal, but tool calling broken (PR #1027) |
| **OpenCode** | — | TUI client | Primary coding agent (full agentic loop with tools) |
| **aider** | — | CLI client | Quick edits, one-shot diffs, git integration |

Ollama and mlx-lm use **different model formats** (GGUF vs MLX) and store files separately. They cannot share downloads.

---

## Quick start

Pull a model and run OpenCode:

```sh
# Pull a model (GGUF, stored at ~/.ollama/models)
ollama pull qwen3-coder:30b

# Start OpenCode (auto-connects to Ollama at localhost:11434)
opencode

# Or use aider
aider
```

---

## Ollama

Installed via Homebrew (`brew "ollama"` in `packages/Brewfile`). On macOS, managed as a
LaunchAgent — starts at login, accessible at `http://127.0.0.1:11434`.

```sh
# Check running models
ollama list

# Pull a model
ollama pull llama3.3:70b

# Run a quick test
ollama run qwen3-coder:30b "hello"

# API endpoint (OpenAI-compatible)
curl http://localhost:11434/v1/models
```

### Context windows

Ollama's default context window (4096 tokens) is too small for agentic tool-use loops — the system
prompt + tool schemas + conversation history fill the window immediately.

`install/opencode.sh` creates context-boosted model aliases automatically:

| Alias | Base model | Context | Memory (weights + KV) |
|---|---|---|---|
| `qwen3-coder:30b-ctx256k` | `qwen3-coder:30b` | 256K | ~78 GB |
| `llama3.3:70b-ctx128k` | `llama3.3:70b` | 128K | ~83 GB |
| `gpt-oss:20b-ctx128k` | `gpt-oss:20b` | 128K | ~39 GB |
| `qwen2.5-coder:7b-ctx128k` | `qwen2.5-coder:7b` | 128K | ~20 GB |

These fit comfortably on an M3 Max 128 GB (unified memory — no CPU/GPU split, Metal accesses all of it).

`gpt-oss:120b` is excluded — confirmed Ollama hang bug with large `num_ctx` for that model.

To recreate aliases after pulling new models:

```sh
bash ~/dotfiles/install/opencode.sh
```

### Model storage

Ollama stores models at `~/.ollama/models` (managed by the Ollama app — not redirected by dotfiles).
On a shared NFS home, point it at scratch if needed:

```sh
OLLAMA_MODELS=/scratch/$USER/ollama/models ollama pull qwen3-coder:30b
```

---

## mlx-lm

Installed via pip (`mlx-lm` in `packages/pip.txt`, tagged `# macos-only`). Apple Silicon only —
runs on Metal, skips CPU. Skipped automatically on Linux by `install/python.sh`.
Not started automatically — launch on demand.

```sh
# Start the server on localhost:8080
mlx_lm.server --model mlx-community/Qwen3-30B-A3B-4bit --port 8080

# Models are stored at $HF_HOME (~/.local/$PLAT/.cache/huggingface)
```

> **Note:** Tool calling in `mlx_lm.server` is currently broken upstream (draft fix in PR #1027).
> Until that merges, use Ollama for agentic workflows. mlx-lm is useful for fast one-shot generation.

`HF_HOME` is set by `.zprofile` to `$_LOCAL_PLAT/.cache/huggingface` — model weights go to scratch
if scratch is configured, never polluting NFS home quotas.

---

## OpenCode

Installed via Homebrew (`brew "opencode"` in `packages/Brewfile`). TUI coding agent that runs a
full agentic loop with file read/write/edit tools. Config at `~/.config/opencode/opencode.json`
(deployed by chezmoi).

```sh
opencode          # launch in current directory
opencode --help   # options
```

The default model is `qwen3-coder:30b-ctx256k` (Ollama). Switch models inside the TUI with `/model`.

OpenCode does **not** auto-detect `OLLAMA_HOST` — the provider is configured explicitly in
`opencode.json` with `baseURL: "http://127.0.0.1:11434/v1"`.

To add a new model to the OpenCode model list, edit `home/dot_config/opencode/opencode.json`
and run `chezmoi apply`. If the model needs a context-boosted alias, add it to
`install/opencode.sh` and re-run it.

---

## aider

Installed via pip (`aider-chat` in `packages/pip.txt`, tagged `# python=3.12` because `scipy` has
no wheels for Python 3.14+). Config at `~/.aider.conf.yml` (deployed by chezmoi as a template):
- **macOS**: defaults to `ollama/qwen3-coder:30b-ctx256k` (local inference)
- **Linux**: empty config — falls through to `ANTHROPIC_API_KEY` or an explicit `--model` flag

```sh
aider                                    # use default model from ~/.aider.conf.yml
aider --model ollama/llama3.3:70b-ctx128k  # override model
aider --model anthropic/claude-opus-4   # use Anthropic API (needs ANTHROPIC_API_KEY)
```

aider has git integration built in — it commits changes automatically with descriptive messages.

---

## run_onchange hooks

chezmoi re-runs the relevant install scripts automatically when tracked files change:

| Trigger file | Script re-run |
|---|---|
| `packages/pip.txt` | `install/local-llm.sh` (verifies mlx-lm/aider binaries) |
| `home/dot_config/opencode/opencode.json` | `install/opencode.sh` (recreates context aliases) |

This means `chezmoi update` after pulling dotfile changes will re-verify the local LLM setup
and recreate any missing model aliases.
