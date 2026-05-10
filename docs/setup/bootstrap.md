# Bootstrap a new machine

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email once. Everything else runs unattended.

### Skip the prompts

Pre-seed name and email to run fully unattended:

```sh
DF_NAME="Your Name" DF_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Values are cached in `~/.config/chezmoi/chezmoi.toml`. On re-runs, they're read from the cache — no prompts.

### From a local clone

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
DF_NAME="Your Name" DF_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

---

## Modes

```sh
bootstrap.sh              # install (default) — full idempotent setup
bootstrap.sh update       # git pull + chezmoi apply + refresh tools
bootstrap.sh upgrade      # update + brew upgrade + cargo upgrade
```

**`update`** pulls the latest dotfiles, applies chezmoi, refreshes zsh plugins, and re-runs all install scripts (which skip already-installed tools). Skips scratch setup and repo cloning.

**`upgrade`** does everything `update` does, plus enables Homebrew upgrades (`DF_BREW_UPGRADE=1`) and forces cargo-binstall to re-check for newer binaries.

---

## macOS

### Requirements

| Requirement | How to get it |
|---|---|
| macOS 13+ (Ventura or later) | — |
| Xcode Command Line Tools | Homebrew prompts automatically, or: `xcode-select --install` |
| Internet access | — |

Sudo is required for the Homebrew installer.

### What gets installed

Paths below use `$LOCAL_PLAT`, which is `$HOME/.local` by default and `$HOME/.local/$PLAT` when [PLAT isolation](plat.md) is enabled. `$ARCH_BIN` is `$LOCAL_PLAT/bin`.

1. **chezmoi** → `$ARCH_BIN/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
   - Shell configs for both **zsh** (`.zprofile`) and **bash** (`.bash_profile`)
   - Both shells do identical PLAT capability detection and PATH setup
3. **oh-my-zsh** + plugins (pure prompt, autosuggestions, fast-syntax-highlighting, completions)
4. **Homebrew** → `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
   - All packages from `packages/Brewfile` — CLI tools, casks, macOS-only apps
   - Includes `rustup` (Homebrew's code-signed build — required for macOS Sequoia+)
5. **Services**: colima registered as a login service (rootless Docker)
6. **macOS defaults**: Dock, Finder, keyboard, trackpad, screenshots, Safari, iTerm2 preferences
7. **Node.js** via nvm → `$LOCAL_PLAT/nvm/`
8. **Rust** toolchain → `$LOCAL_PLAT/rustup/` + `$LOCAL_PLAT/cargo/`
   - Homebrew's `rustup` (code-signed), required on macOS Sequoia+ where the linker enforces `com.apple.provenance`
   - `cargo-binstall` downloads pre-built binaries from GitHub releases when available, falls back to source
   - Cargo tools install to `$LOCAL_PLAT/cargo/bin/`
9. **Python** via uv → `$LOCAL_PLAT/uv/tools/<tool>/` (one isolated venv per CLI tool), entrypoints in `$ARCH_BIN`
10. **Claude Code** native binary → `$ARCH_BIN/claude` + plugins + MCP servers + overlay skills
11. **Codex CLI** native binary → `$ARCH_BIN/codex`, plus managed config + hooks under `~/.codex/`
12. **Cursor / VS Code** — settings symlinked from `home/dot_cursor/`; extensions installed from `packages/{cursor,vscode}-extensions.txt`
13. **CMake toolchain files** → `$LOCAL_PLAT/cmake/toolchains/`
    - Versioned files: `llvm-21.cmake`, `llvm-22.cmake`, `gcc-13.cmake`, `gcc-15.cmake`, plus shared `_brew.cmake`
    - `~/.profile` sets `CMAKE_TOOLCHAIN_FILE` to the highest installed LLVM toolchain automatically
    - Switch at runtime with the `tc` shell function (e.g. `tc gcc-15`, `tc llvm-22`)
14. **Local LLM tooling** — HuggingFace cache + Ollama context-boosted model aliases
    - Creates `$LOCAL_PLAT/.cache/huggingface` for mlx-lm weights
    - Context-boosted aliases (e.g. `qwen3-coder:30b-ctx256k`) created if the base model is pulled
    - Skipped gracefully if Ollama is not installed
15. **Blender MCP** addon — installs `addon.py` into the active Blender profile and enables it
16. **Auth** (opt-in: `DF_DO_AUTH=1`) — guided service-token setup; see [Auth](auth.md)
17. **Overlays** — runs `bootstrap.sh` of any `dotfiles-*/` overlay alongside this repo; see [Overlays](overlays.md)

Total time: ~2 minutes on subsequent runs (idempotent, mostly bottle pours); ~5–10 minutes on a fresh machine.

---

## Linux

### Requirements

| Requirement | Notes |
|---|---|
| x86\_64 or aarch64 | — |
| `git` and `curl` | Pre-installed on most systems |
| Internet access | — |

No sudo required. No Docker or Podman needed.

### What gets installed

Paths use `$LOCAL_PLAT`, which is `$HOME/.local` by default (or `$HOME/.local/$PLAT` with [PLAT isolation](plat.md) enabled — recommended for shared NFS homes).

1. **chezmoi** → `$ARCH_BIN/chezmoi` (`$ARCH_BIN` = `$LOCAL_PLAT/bin`)
2. **Dotfiles** applied via `chezmoi apply`
   - Shell configs for both **zsh** (`.zprofile`) and **bash** (`.bash_profile`)
3. **oh-my-zsh** + plugins
4. **Homebrew** → `$LOCAL_PLAT/brew/` (native install, no Docker/Podman needed)
   - Installs Homebrew's own glibc 2.35 first — binaries are fully self-contained
   - Most packages pour as precompiled bottles; glibc builds from source (~2 min) on first run
   - Custom Python@3.14 patches applied automatically for Linux compatibility
5. **Node.js** via nvm → `$LOCAL_PLAT/nvm/`
6. **Rust** via `sh.rustup.rs` → `$LOCAL_PLAT/rustup/` + `$LOCAL_PLAT/cargo/`
   - `cargo-binstall` downloads pre-built binaries from GitHub releases when available, falls back to source
7. **Python** via uv → `$LOCAL_PLAT/uv/tools/<tool>/` (per-CLI-tool venvs), entrypoints in `$ARCH_BIN`
8. **Claude Code** native binary → `$ARCH_BIN/claude` + plugins + MCP servers
9. **Codex CLI** native binary → `$ARCH_BIN/codex`
10. **Cursor / VS Code** — extensions from `packages/{cursor,vscode}-extensions.txt`
11. **CMake toolchain files** → `$LOCAL_PLAT/cmake/toolchains/` (`llvm-21/22.cmake`, `gcc-13/15.cmake`, `_brew.cmake`)
    - `~/.profile` auto-sets `CMAKE_TOOLCHAIN_FILE` to the highest installed LLVM toolchain
    - Switch with the `tc` shell function (e.g. `tc gcc-15`, `tc llvm-22`)
12. **Local LLM tooling** — HuggingFace cache + Ollama context-boosted model aliases (skipped if Ollama not installed)
13. **Auth** (opt-in: `DF_DO_AUTH=1`) — guided token setup; see [Auth](auth.md)
14. **Overlays** — runs `bootstrap.sh` of any `dotfiles-*/` overlay; see [Overlays](overlays.md)

Total time: ~5 minutes on a fast connection.

---

## Skipping steps

Any step can be disabled with an environment variable:

```sh
DF_DO_SCRATCH=0              # skip scratch space symlink setup
DF_DO_DIRS=0                 # skip home directory creation (~/dev, ~/bones, ~/misc)
DF_DO_PACKAGES=0             # skip Homebrew + brew bundle
DF_DO_MACOS_SERVICES=0       # skip colima service setup (macOS)
DF_DO_MACOS_SETTINGS=0       # skip macOS settings (Dock, Finder, keyboard, etc.)
DF_DO_MACOS_QUICK_ACTIONS=0  # skip Finder Quick Actions install (macOS)
DF_DO_ZSH=0                  # skip oh-my-zsh
DF_DO_NODE=0                 # skip nvm + Node.js + global npm packages
DF_DO_RUST=0                 # skip rustup + cargo tools
DF_DO_PYTHON=0               # skip uv + per-tool venvs
DF_DO_CLAUDE=0               # skip Claude Code install + plugins + MCP servers
DF_DO_CODEX=0                # skip Codex CLI install
DF_DO_CURSOR=0               # skip Cursor settings symlinks + extension install
DF_DO_VSCODE=0               # skip VS Code extension install
DF_DO_CMAKE=0                # skip CMake toolchain file deployment
DF_DO_LOCAL_LLM=0            # skip local LLM setup (HuggingFace cache + Ollama context aliases)
DF_DO_BLENDER_MCP=0          # skip Blender MCP addon install
DF_DO_AUTH=1                 # run interactive API token setup (default 0)
DF_DO_OVERLAYS=0             # skip all overlay bootstraps (dotfiles-*/bootstrap.sh)
DF_USE_PLAT=1                # opt in to per-PLAT directory isolation (default 0; flat layout)
DF_BREW_UPGRADE=0            # skip Homebrew upgrades (macOS default: 1, Linux default: 0)
```

The complete reference lives at [Env vars](../reference/env-vars.md).

Example — dotfiles only, no runtimes:

```sh
DF_DO_PACKAGES=0 DF_DO_ZSH=0 DF_DO_NODE=0 \
DF_DO_RUST=0 DF_DO_PYTHON=0 DF_DO_CLAUDE=0 \
~/dotfiles/bootstrap.sh
```

---

## Debug mode

For verbose output with command timing:

```sh
DF_DEBUG=1 ~/dotfiles/bootstrap.sh
```

Shows `[dbug]` lines for every command executed by `run_logged`, including exit codes and elapsed time.

---

## Shared home directories (NFS/GPFS)

If you share `$HOME` across multiple machines with different CPU architectures, **enable PLAT isolation**:

```sh
DF_USE_PLAT=1 ~/dotfiles/bootstrap.sh
```

(Or persist it in chezmoi data: `chezmoi edit ~/.config/chezmoi/chezmoi.toml` and set `use_plat = true`.)

With PLAT on, each machine installs compiled tools to its own `~/.local/$PLAT/` directory:

| Machine | PLAT | Where tools live |
|---|---|---|
| AVX-512 Linux (e.g. Ice Lake) | `plat_Linux_x86-64-v4` | `~/.local/plat_Linux_x86-64-v4/` |
| AVX2 Linux (e.g. Haswell/Zen2) | `plat_Linux_x86-64-v3` | `~/.local/plat_Linux_x86-64-v3/` |
| ARM Linux | `plat_Linux_aarch64` | `~/.local/plat_Linux_aarch64/` |
| Apple Silicon | `plat_Darwin_arm64` | `~/.local/plat_Darwin_arm64/` |

Text configs (dotfiles) are arch-neutral and shared freely across all machines. See [PLAT isolation](plat.md) for the deeper explanation, the decommission script, and the failure modes that PLAT exists to prevent.

### Scratch space (large quota environments)

If your home directory has a small quota (common on HPC NFS mounts), direct large directories to local scratch storage:

```sh
DF_SCRATCH=/scratch/$USER \
DF_NAME="Your Name" DF_EMAIL="you@example.com" \
~/dotfiles/bootstrap.sh
```

This symlinks large directories to `$DF_SCRATCH/.paths/` before any tools are installed, so the multi-GB Homebrew prefix and caches never touch NFS.

Default directories redirected to scratch (controlled by `DF_LINKS`):

- `~/.local` — PLAT directories, Homebrew prefix, tool binaries
- `~/.cache` — ccache, sccache, pip/uv cache
- `~/.vscode` / `~/.vscode-server` — VS Code extensions and data
- `~/.cursor` / `~/.cursor-server` — Cursor IDE data
- `~/.nv` — NVIDIA shader and OptiX cache
- `~/.npm` — npm cache
- `~/.claude` — Claude Code data and cache
- `~/.oh-my-zsh` / `~/.oh-my-zsh-custom` — oh-my-zsh and plugins

---

## Auth (API tokens)

See the dedicated [Auth](auth.md) page for the full walkthrough. Quick reference:

```sh
bash ~/dotfiles/install/auth.sh                  # walk every service interactively
bash ~/dotfiles/install/auth.sh status           # show current state, no prompts
bash ~/dotfiles/install/auth.sh huggingface      # set/update one service
bash ~/dotfiles/install/auth.sh gh               # `gh auth login` (browser flow)

# Or during bootstrap:
DF_DO_AUTH=1 ~/dotfiles/bootstrap.sh
```

Covers **GitHub**, **Anthropic**, **OpenAI**, **Cloudflare**, **HuggingFace**, plus a separate `gh auth login` flow for the Claude GitHub MCP. Tokens land in `~/.<service>.env` files (chmod 600) and are auto-sourced by install scripts and login shells. Each prompt shows a `skip if:` hint — most users only set 1–2 of them.
