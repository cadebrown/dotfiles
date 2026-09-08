# Local AI coding

Local LLM inference on macOS Apple Silicon (M-series) — no API keys, no rate
limits, no cloud — used as the default backend for **opencode** and **pi**
(and as a generic OpenAI-compatible endpoint for anything else).

## Overview

| Layer | Tool | Where it lives |
|---|---|---|
| **Server** | mlx-openai-server | Started and checked on demand by `local-agent`; port 8080. Login auto-start remains off by default. |
| **Server (fallback)** | Ollama | LaunchAgent (**auto-start off by default**), port 11434, OpenAI-compat |
| **Client** | opencode, pi | Both point at `localhost:8080/v1` by default on macOS |
| **Cloud** | Anthropic, OpenAI | Available everywhere via `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` |

MLX is the **primary backend** because it's roughly 2-3× faster than Ollama
(llama.cpp) on the M3 Max for the same quants, and `mlx-openai-server` adds
OpenAI tool-call parsing on top — which `mlx_lm.server` upstream still lacks.
Ollama remains installed as a plain fallback.

## Quick start

```sh
# Explicit local launch: verify the configured MLX model, then open the agent.
local-agent pi
local-agent opencode
local-agent status
local-agent stop                  # stop only the backend this helper started

# Foreground server for a custom model:
mlxserve                          # default: Qwen3.6-27B 8-bit (served as "qwen3.6-27b")
mlxserve qwen3.6-35b-a3b          # MoE alternative — fast tokens (3B active)
mlxserve coder-next               # Qwen3-Coder-Next 80B/3B MoE (no thinking)

# Opt in to a persistent login service only when wanted:
mlxstart
mlxstatus
mlxstop                           # bootout + disable across logins
```

`local-agent` reads Pi's current settings or OpenCode's effective configuration,
including its selected agent. It verifies the exact model at the configured
loopback endpoint. A healthy existing server is reused and left running. An
occupied port or a server offering another model causes a clear failure; it
never replaces that process or chooses a cloud model. Client arguments pass
through, with the resolved model made explicit for the launch.
OpenCode keeps its existing `--auto` launch behavior and refreshes the same
GitHub/Google MCP credentials as the interactive shell wrapper. Supplied
environment values win; no login flow or additional credential source is used.

When startup is needed, the helper uses the managed MLX plist's arguments and
the current `mlx-openai-server` executable. It runs outside launchd, serializes
concurrent starts, and waits for model readiness before launching the client.
It does not alter login-service enablement. The server stays available after
the client exits; `local-agent stop` verifies its saved process identity before
sending SIGTERM. Logs and its process receipt live under
`$LOCAL_PLAT/share/mlxserve/on-demand/`.

Startup uses cached weights only. Missing or incomplete models fail without a
download; pre-pull them explicitly with the command below. The default readiness
limit is 180 seconds, adjustable with `DF_MLX_START_TIMEOUT`.

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
commented entries are one `mlxpull <alias>` away. `bootstrap.sh upgrade`
also pulls missing models declared in this list when local inference is selected.

`DF_PROFILE=full` selects the MLX packages and verification by default.
`DF_PROFILE=core` skips local inference by default, matching its smaller Python
manifest. `DF_DO_LOCAL_LLM` remains an explicit override. OpenCode's npm install
and config sync are independent; `DF_DO_OPENCODE=0` skips only its reconciliation.

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

### OpenCode capability routing

`build`, `plan`, and the read-only `review` agent expose five MCP namespaces:
Context7, QMD, OpenAI developer docs, Rust docs, and crates.io. The full installed
MCP catalog remains configured. OpenCode 1.18.29 includes enabled tool schemas in
each request, so loading every integration can overwhelm a local model before
the first task starts. The installer generates global namespace denies and
agent-specific allows using OpenCode's [permission rules](https://dev.opencode.ai/docs/agents/#permissions).
It preserves the existing model, effort, provider, and MCP activation settings.

Select a specialist in the agent picker, mention it with `@`, or have the current
agent delegate a bounded task. Each specialist can run as a primary or subagent
(`mode: all`) and has no model override: delegated work inherits the caller's
model; primary use follows the current session/global model selection.

| Agent | MCP capabilities |
|---|---|
| `research` | Web search, extraction, papers, citations, model repositories |
| `browser` | Chrome DevTools |
| `creative` | Blender |
| `desktop` | macOS app automation |
| `cloud` | Cloudflare and Google Cloud |
| `workspace` | Google mail, calendars, and documents |
| `math` | Lean, Mathlas, and Wolfram |
| `repository` | GitHub repositories, issues, and pull requests |

The groups follow the active shared registry profiles. An additional or custom
MCP server outside these groups gets a discoverable `mcp-<namespace>` specialist,
with only that server's tools enabled. Inspect the `agent` and `mcp` objects in
`~/.config/opencode/opencode.json` for the exact current map. A server previously
disabled stays disabled; selecting its specialist does not start it. Review
cannot edit or delegate, and retains its read-only shell rules.

```sh
bash ~/dotfiles/install/opencode.sh sync-config
local-agent opencode run --agent browser "Inspect the local app"
```

Scoping controls which schemas reach the model. OpenCode can still connect to
configured MCP servers during startup; this is not lazy server discovery.

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

Installed via Homebrew (`brew "ollama"`). Has a LaunchAgent on macOS but
**auto-start is off by default** (`DF_START_LOCAL_SERVICES=1` to opt in, or run
`ollama serve`); when running it serves `http://127.0.0.1:11434`. No model fleet is maintained
for it; an ad-hoc pull (`ollama pull qwen3-coder:30b`) is one command away.
(The old context-boosted alias machinery was removed — nothing consumed it.)

Bootstrap migrates an existing Ollama.app backend only after confirming that it
owns port 11434, has no loaded models, and has no established connections. Busy
or unrecognized servers are left untouched and the installer reports the reason.
The migration disables only Ollama.app's helper, stops its exact recognized
processes with SIGTERM, and verifies that all model names and digests survive.
With login services off, the formula uses `brew services run` for the current
session. A failed handoff attempts to restore the app backend and its previous enablement.
The app and model files remain installed.

OpenCode's older Homebrew formula is retired only after the npm executable
passes its runtime check, Homebrew reports no dependents, and a verified rollback
copy exists. Neither migration touches agent configuration or model data.
Receipts are under `$LOCAL_PLAT/share/dotfiles/rollback/`.

## run_onchange hooks

| Trigger file | Script re-run |
|---|---|
| `packages/pip-full.txt` | `install/local-llm.sh` (verifies binaries) |
| `home/dot_config/opencode/create_private_opencode.json.tmpl` | `install/opencode.sh` (config and capability scopes) |

`chezmoi update` after pulling dotfile changes re-verifies the setup.
