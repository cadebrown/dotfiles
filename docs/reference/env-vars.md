# Environment variables

Complete reference for `DF_*` variables and the tool-standard ones this repo cares about. All `DF_*` flags are read in `install/_lib.sh` or `bootstrap.sh`. Set in your shell, prepend to a single command, or persist via chezmoi data.

## Configuration

| Var | Default | What it does |
|---|---|---|
| `DF_NAME` | (prompts) | Display name. Pre-seed to skip the chezmoi prompt on first run. |
| `DF_EMAIL` | (prompts) | Email. Pre-seed to skip the chezmoi prompt on first run. |
| `DF_REPO` | `cadebrown/dotfiles` | GitHub `owner/repo` slug used by curl-bootstrap. Override to fork. |
| `DF_PATH` | (auto-detect) | Where the repo lives. Local runs use the script directory; piped runs clone to `$HOME/dotfiles`. |
| `DF_LINK` | `$HOME/dotfiles` | Symlink in `$HOME` that points at `DF_PATH`. |
| `DF_DIRS` | `dev:bones:misc` | Colon-separated list of subdirs created in `$HOME` by `install/dirs.sh`. |

## Behavior toggles

| Var | Default | What it does |
|---|---|---|
| `DF_USE_PLAT` | `0` | Per-PLAT directory isolation. `1` enables `$LOCAL_PLAT=$HOME/.local/$PLAT`; `0` collapses to `$HOME/.local`. Accepts `1\|true\|yes\|on` (case-insensitive). See [PLAT isolation](../setup/plat.md). |
| `DF_BREW_UPGRADE` | `0` | Whether to upgrade existing formulae/casks. Auto-set to `1` in `upgrade` mode on both platforms. |
| `DF_BREW_DOWNLOAD_CONCURRENCY` | `4` | Maximum simultaneous Homebrew bottle/cask downloads. |
| `DF_BREW_UPGRADE_CASKS` | `auto` | Upgrade greedy casks only when sudo is already cached; set `0` to skip or run `sudo -v`/set `1` to permit prompts. |
| `DF_STRICT_UPGRADE` | `1` | Run `install/audit-versions.sh --strict` after `bootstrap.sh upgrade`; set `0` for a report-only audit. |
| `DF_MCP_PROFILES` | (unset) | Colon/comma/space-separated opt-in MCP profiles such as `research-scite`, `biomed`, or `publish`. Core servers are always rendered. |
| `DF_DEBUG` | `0` | Set to `1` for verbose `[dbug]` output with timing info on every `run_logged` command. |
| `DF_FORCE` | `0` | Used by `install/plat-decommission.sh` to skip the deletion confirmation prompt. |
| `DF_CARGO_STRATEGIES` | (unset) | Override `cargo binstall --strategies`. E.g. `compile` to skip GitHub release fetchers (useful behind a VPN). |

## Scratch space

| Var | Default | What it does |
|---|---|---|
| `DF_SCRATCH` | (unset) | Path to scratch root. Setting this enables scratch mode (symlinks heavy `$HOME` dirs). |
| `DF_SCRATCH_LINK` | `$HOME/scratch` | The `$HOME` symlink that points at scratch. Bootstrap creates this if `DF_SCRATCH` is set. |
| `DF_LINKS` | `~/.local:~/.cache:~/.cass:~/.vscode:~/.vscode-server:~/.cursor-server:~/.nv:~/.npm:~/.oh-my-zsh:~/.oh-my-zsh-custom:~/kb:~/.computelab:~/.agent-browser:~/.gradle` | Colon-separated top-level dirs to redirect to scratch. TinyTeX lives below `$LOCAL_PLAT`; `~/.cursor` is chezmoi-owned. |
| `DF_CONFIG_LINKS` | `Code` | Colon-separated `~/.config` subdir names to redirect to scratch (never `~/.config` itself — chezmoi owns it). |
| `DF_CURSOR_LINKS` | `projects:worktrees` | Colon-separated `~/.cursor` subdir names to redirect to scratch (never `~/.cursor` itself — chezmoi owns it). |
| `DF_CLAUDE_LINKS` | `projects:plugins:file-history` | Colon-separated `~/.claude` subdir names to redirect to scratch (never `~/.claude` itself — chezmoi owns it). Drop `projects` to keep history + memory on NFS. |
| `DF_CODEX_LINKS` | `sessions:generated_images:cache:plugins:attachments:shell_snapshots:log:backups:.tmp:tmp` | Colon-separated `~/.codex` subdir names to redirect to scratch (never `~/.codex` itself). Top-level `*.sqlite` files ride along. Set empty to skip `~/.codex` entirely. |

The five `*_LINKS` vars treat a set-but-empty value as "migrate nothing here"; unset restores the default.

See [Scratch space](../setup/scratch.md).

## Skip flags

Each `DF_DO_*` flag defaults to `1` (run) except where the table says otherwise.
Set a flag to `0` to skip it.

| Var | Step | Skips |
|---|---|---|
| `DF_DO_SCRATCH` | 0 | Scratch space symlink setup (auto-`0` in update/upgrade modes) |
| `DF_DO_DIRS` | 0.1 | `~/dev`, `~/bones`, `~/misc` creation |
| `DF_DO_PACKAGES` | 4 | Homebrew + `brew bundle` |
| `DF_DO_LLDB` | 4 | LLDB debugger and `lldb-dap` adapter |
| `DF_DO_MACOS_SERVICES` | 5 | Colima service registration (macOS) |
| `DF_DO_MACOS_SETTINGS` | 5.5 | Dock/Finder/keyboard/etc. defaults (macOS) |
| `DF_DO_MACOS_QUICK_ACTIONS` | 5.6 | Finder Quick Actions install (macOS) |
| `DF_DO_ZSH` | 3 | oh-my-zsh + plugins |
| `DF_DO_PYTHON` | 6 | uv + per-tool isolated venvs |
| `DF_DO_NODE` | 6 | nvm + Node.js + global npm packages |
| `DF_DO_RUST` | 6 | rustup + cargo tools |
| `DF_DO_GO` | 6 | Go CLI tools from `go.txt` |
| `DF_DO_JULIA` | 6 | Juliaup release channel and PLAT-isolated depots |
| `DF_DO_LEAN` | 6 | Lean 4 toolchain (elan + the pinned default toolchain) |
| `DF_DO_LATEX` | 6 | TeX distribution (MacTeX verify on macOS, TinyTeX on Linux) |
| `DF_DO_QUARTO` | 4 | Quarto cask verification on macOS or rootless release install on Linux |
| `DF_DO_CLAUDE` | 6 | Claude Code binary + plugins + MCP servers + overlay skills |
| `DF_DO_CODEX` | 6 | Codex CLI binary + managed config + hooks |
| `DF_DO_CLAUDE_DESKTOP` | 6 | Claude Desktop tracked preferences (macOS) |
| `DF_DO_CODEX_DESKTOP` | 6 | Codex desktop app tracked preferences (macOS) |
| `DF_DO_LINEARMOUSE` | 6 | LinearMouse tracked settings (macOS) |
| `DF_DO_CURSOR` | 6 | Cursor settings symlinks + extensions. Defaults to `1` on macOS and `0` on Linux; set `1` explicitly when a Linux Cursor CLI is installed. |
| `DF_DO_VSCODE` | 6 | VS Code settings + extensions. Defaults to `1` on macOS and `0` on Linux; set `1` explicitly when a Linux `code` CLI is installed. |
| `DF_DO_CMAKE` | 6 | CMake toolchain file deployment |
| `DF_DO_LOCAL_LLM` | 6.5 | Local LLM tooling (HuggingFace cache + binary checks) |
| `DF_DO_MEMORY` | 6.6 | Agent memory stack (cass + qmd + ~/kb + daemons) |
| `DF_DO_SKILLS` | 6.65 | Agent skills from `agent-skills.txt` |
| `DF_DO_BLENDER_MCP` | 6.7 | **Default `1` on macOS, `0` on Linux**. Set to `0` to skip the Blender MCP addon. |
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
| `ELAN_HOME` | `_lib.sh` | `$LOCAL_PLAT/elan` (Lean toolchains — arch-specific, ~1.5 GB each) |
| `JULIAUP_DEPOT_PATH` | `_lib.sh` | `$LOCAL_PLAT/julia/juliaup` |
| `JULIA_DEPOT_PATH` | `_lib.sh` | `$LOCAL_PLAT/julia/depot` (compiled per-arch artifacts) |
| `UV_TOOL_BIN_DIR` | `_lib.sh` | `$ARCH_BIN` (where uv tool entrypoints land) |
| `UV_TOOL_DIR` | `_lib.sh` | `$LOCAL_PLAT/uv/tools` (per-tool venvs) |
| `UV_PYTHON_INSTALL_DIR` | `_lib.sh` | `$LOCAL_PLAT/uv/python` (uv-managed Python) |
| `PYTHON_ENV` | `_lib.sh` | `$LOCAL_PLAT/python` (small environment behind plain `python`, including `packages/python.txt`) |
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
