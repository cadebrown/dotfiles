# Environment variables

Complete reference for `DF_*` variables and the tool-standard ones this repo cares about. All `DF_*` flags are read in `install/_lib.sh` or `bootstrap.sh`. Set in your shell, prepend to a single command, or persist via chezmoi data.

## Configuration

| Var | Default | What it does |
|---|---|---|
| `DF_NAME` | (prompts) | Display name. Pre-seed to skip the chezmoi prompt on first run. |
| `DF_EMAIL` | (prompts) | Email. Pre-seed to skip the chezmoi prompt on first run. |
| `DF_REPO` | `cadebrown/dotfiles` | GitHub `owner/repo` slug used by curl-bootstrap. Override to fork. |
| `DF_PATH` | (auto-detect) | Where the dotfiles repo lives on disk. Defaults to the script's parent dir. |
| `DF_LINK` | `$HOME/dotfiles` | Symlink in `$HOME` that points at `DF_PATH`. |
| `DF_DIRS` | `dev:bones:misc` | Colon-separated list of subdirs created in `$HOME` by `install/dirs.sh`. |

## Behavior toggles

| Var | Default | What it does |
|---|---|---|
| `DF_USE_PLAT` | `0` | Per-PLAT directory isolation. `1` enables `$LOCAL_PLAT=$HOME/.local/$PLAT`; `0` collapses to `$HOME/.local`. Accepts `1\|true\|yes\|on` (case-insensitive). See [PLAT isolation](../setup/plat.md). |
| `DF_BREW_UPGRADE` | `1` (macOS), `0` (Linux) | Whether to run `brew upgrade` and `brew upgrade --cask --greedy`. Auto-set to `1` in `upgrade` mode. |
| `DF_DEBUG` | `0` | Set to `1` for verbose `[dbug]` output with timing info on every `run_logged` command. |
| `DF_FORCE` | `0` | Used by `install/plat-decommission.sh` to skip the deletion confirmation prompt. |
| `DF_CARGO_STRATEGIES` | (unset) | Override `cargo binstall --strategies`. E.g. `compile` to skip GitHub release fetchers (useful behind a VPN). |

## Scratch space

| Var | Default | What it does |
|---|---|---|
| `DF_SCRATCH` | (unset) | Path to scratch root. Setting this enables scratch mode (symlinks heavy `$HOME` dirs). |
| `DF_SCRATCH_LINK` | `$HOME/scratch` | The `$HOME` symlink that points at scratch. Bootstrap creates this if `DF_SCRATCH` is set. |
| `DF_LINKS` | `~/.local:~/.cache:~/.vscode:~/.vscode-server:~/.cursor:~/.cursor-server:~/.nv:~/.npm:~/.oh-my-zsh:~/.oh-my-zsh-custom` | Colon-separated dirs to redirect to scratch. |

See [Scratch space](../setup/scratch.md).

## Skip flags

Each `DF_DO_*` flag defaults to `1` (run). Set to `0` to skip.

| Var | Step | Skips |
|---|---|---|
| `DF_DO_SCRATCH` | 0 | Scratch space symlink setup (auto-`0` in update/upgrade modes) |
| `DF_DO_DIRS` | 0.1 | `~/dev`, `~/bones`, `~/misc` creation |
| `DF_DO_PACKAGES` | 4 | Homebrew + `brew bundle` |
| `DF_DO_MACOS_SERVICES` | 5 | Colima service registration (macOS) |
| `DF_DO_MACOS_SETTINGS` | 5.5 | Dock/Finder/keyboard/etc. defaults (macOS) |
| `DF_DO_MACOS_QUICK_ACTIONS` | 5.6 | Finder Quick Actions install (macOS) |
| `DF_DO_ZSH` | 3 | oh-my-zsh + plugins |
| `DF_DO_NODE` | 6 | nvm + Node.js + global npm packages |
| `DF_DO_RUST` | 6 | rustup + cargo tools |
| `DF_DO_PYTHON` | 6 | uv + per-tool isolated venvs |
| `DF_DO_CLAUDE` | 6 | Claude Code binary + plugins + MCP servers + overlay skills |
| `DF_DO_CODEX` | 6 | Codex CLI binary + managed config + hooks |
| `DF_DO_CURSOR` | 6 | Cursor settings symlinks + extensions |
| `DF_DO_VSCODE` | 6 | VS Code extensions |
| `DF_DO_CMAKE` | 6 | CMake toolchain file deployment |
| `DF_DO_LOCAL_LLM` | 6.5 | Local LLM tooling (HuggingFace cache, Ollama context aliases) |
| `DF_DO_BLENDER_MCP` | 6.6 | Blender MCP addon install |
| `DF_DO_AUTH` | 7 | **Default `0`**. Set to `1` to run interactive token setup. |
| `DF_DO_OVERLAYS` | 8 | Skip all overlay bootstrap scripts |

## Internal (set by `_lib.sh`, not user-facing)

These are exported by `_lib.sh` for install scripts to consume — don't override unless you know why.

| Var | Source | Value |
|---|---|---|
| `OS` | `_lib.sh` | `darwin` or `linux` |
| `ARCH` | `_lib.sh` | `x86_64` or `aarch64` (normalized) |
| `PLAT` | `_lib.sh` | Detected platform name (e.g. `plat_Darwin_arm64`); empty if no spec matches |
| `LOCAL_PLAT` | `_lib.sh` | Install root: `$HOME/.local` (flat) or `$HOME/.local/$PLAT` (PLAT-on) |
| `ARCH_BIN` | `_lib.sh` | `$LOCAL_PLAT/bin` |
| `RUSTUP_HOME` | `_lib.sh` | `$LOCAL_PLAT/rustup` |
| `CARGO_HOME` | `_lib.sh` | `$LOCAL_PLAT/cargo` |
| `CARGO_TARGET_DIR` | `_lib.sh` | `$LOCAL_PLAT/cargo-build` (workaround for macOS Sequoia ar/ld in `/var/folders/`) |
| `NVM_DIR` | `_lib.sh` | `$LOCAL_PLAT/nvm` |
| `UV_TOOL_BIN_DIR` | `_lib.sh` | `$ARCH_BIN` (where uv tool entrypoints land) |
| `UV_TOOL_DIR` | `_lib.sh` | `$LOCAL_PLAT/uv/tools` (per-tool venvs) |
| `UV_PYTHON_INSTALL_DIR` | `_lib.sh` | `$LOCAL_PLAT/uv/python` (uv-managed Python) |
| `CONAN_HOME` | `_lib.sh` | `$LOCAL_PLAT/conan2` |
| `DF_ROOT` | `_lib.sh` | The dotfiles repo root (parent of `install/`) |
| `DF_PACKAGES` | `_lib.sh` | `$DF_ROOT/packages` |
| `DF_OVERLAYS` | `_lib.sh` | Bash array of discovered `dotfiles-*/` overlay paths |
| `DF_INSTALL_DIR` | `bootstrap.sh` | `$DF_ROOT/install` |
| `DF_MODE` | `bootstrap.sh` | `install`, `update`, or `upgrade` |
| `GIT_CONFIG_GLOBAL` | `_lib.sh` | Forced to `/dev/null` so install scripts aren't affected by SSH-rewriting gitconfig |

## Pre-seeding chezmoi

These get cached in `~/.config/chezmoi/chezmoi.toml` on first init and don't re-prompt:

| chezmoi data key | Source | Notes |
|---|---|---|
| `name` | `DF_NAME` env or interactive prompt | Used in templates as `{{ .name }}` |
| `email` | `DF_EMAIL` env or interactive prompt | Used in templates as `{{ .email }}` |
| `use_plat` | `DF_USE_PLAT` env or `false` default | Used in templates as `{{ .use_plat }}` to gate PLAT-isolated paths |

Edit `~/.config/chezmoi/chezmoi.toml` directly to change these without re-running `chezmoi init`.
