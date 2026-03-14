# cade's dotfiles

Personal dotfiles for macOS and Linux. One command bootstraps a complete dev environment -- idempotent, safe on shared NFS home directories across CPU architectures. No sudo required on Linux.

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email once. Re-run anytime to converge.

---

## What gets installed

### Dotfiles and shell

[chezmoi](https://chezmoi.io) manages dotfiles as templates in `home/` and applies them to `~/`. Both **zsh** and **bash** get identical login profiles with PLAT detection, PATH setup, and tool activation.

- **zsh**: oh-my-zsh with [pure](https://github.com/sindresorhus/pure) prompt, autosuggestions, fast-syntax-highlighting, completions, and lazy nvm loading (~140ms startup)
- **bash**: minimal config with git branch prompt, shared aliases, zoxide, fzf completions
- **git**: global config with name/email from chezmoi data, delta as pager
- **SSH**: templated config from `home/dot_ssh/config.tmpl`

### Packages

A single `packages/Brewfile` drives both platforms. On macOS, Homebrew installs native bottles plus casks (GUI apps). On Linux, Homebrew installs to a custom per-CPU prefix (`~/.local/$PLAT/brew/`) with its own glibc -- fully self-contained, no sudo.

`if OS.mac?` blocks in the Brewfile handle macOS-only casks and tools; Linux skips them silently.

### Languages

| Language | Tool | Install location | Package list |
| --- | --- | --- | --- |
| **Rust** | rustup + cargo-binstall | `$LOCAL_PLAT/rustup/`, `$LOCAL_PLAT/cargo/` | `packages/cargo.txt` |
| **Node.js** | nvm (lazy-loaded in zsh) | `$LOCAL_PLAT/nvm/` | `packages/npm.txt` |
| **Python** | uv + venv | `$LOCAL_PLAT/venv/` | `packages/pip.txt` |

Rust tools are installed via `cargo-binstall` which downloads pre-built binaries from GitHub releases when available, falling back to source compilation. On macOS, rustup comes from Homebrew (code-signed, required on Sequoia+ where the linker enforces provenance).

### AI tools

- **Claude Code** -- native binary downloaded from Anthropic's release bucket, plus plugins from `packages/claude-plugins.txt` and MCP servers from `packages/claude-mcp.txt`
- **Codex CLI** -- native binary from GitHub releases

### macOS-specific

- **System settings** (`install/macos-settings.sh`) -- Dock autohide, Finder extensions/path bar, fast key repeat, tap to click, PNG screenshots, Safari dev menu, iTerm2 prefs
- **Services** (`install/macos-services.sh`) -- Colima registered as a login service (rootless Docker without Docker Desktop)

### Auth (opt-in)

`install/auth.sh` is an interactive helper that creates `~/.{service}.env` files (chmod 600) for `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, and `OPENAI_API_KEY`. These are sourced automatically by all install scripts. Run during bootstrap with `DF_DO_AUTH=1` or standalone anytime.

### Home directories

`install/dirs.sh` creates `~/dev`, `~/bones`, and `~/misc` (configurable via `DF_DIRS`). On systems with scratch space, these become symlinks directly under `$SCRATCH/` for fast local storage.

---

## PLAT isolation

Every compiled binary lives under `~/.local/$PLAT/` where `PLAT` is detected from CPU features at shell startup. On a shared NFS home, each machine installs into its own PLAT directory -- binaries are isolated, text configs are shared freely.

```
~/.local/plat_Linux_x86-64-v4/    # AVX-512 (Ice Lake+, Zen 4+)
~/.local/plat_Linux_x86-64-v3/    # AVX2 (Haswell+, Zen 2+)
~/.local/plat_Linux_x86-64-v2/    # SSE4.2 (Nehalem+)
~/.local/plat_Linux_aarch64/       # ARM Linux (Graviton, Ampere)
~/.local/plat_Darwin_arm64/        # Apple Silicon
~/.local/plat_Darwin_x86-64/       # Intel Mac
```

The shell profile detects the current machine's PLAT and puts only that directory's paths on PATH. One home directory, many machines, no conflicts.

Each PLAT also gets CPU-specific compiler flags (`-march=x86-64-v3`, etc.) via `.plat_env.sh` scripts, so tools compiled from source use the best available instruction set.

---

## macOS vs Linux

| | macOS | Linux |
| --- | --- | --- |
| Packages | Homebrew at `/opt/homebrew` | Homebrew at `~/.local/$PLAT/brew/` (custom prefix, bundled glibc) |
| Rust | Homebrew `rustup` (code-signed for Sequoia) | `sh.rustup.rs` |
| System settings | Dock, Finder, keyboard, trackpad, Safari, iTerm2 | -- |
| Services | Colima (rootless Docker) | -- |
| sudo required | Yes (Homebrew installer) | No |

---

## Bootstrap modes

```sh
bootstrap.sh              # install (default) — full idempotent setup
bootstrap.sh update       # git pull + chezmoi apply + refresh tools
bootstrap.sh upgrade      # update + brew upgrade + cargo upgrade
```

Any step can be skipped with `DF_DO_*=0` env vars. See [Bootstrap](setup/bootstrap.md) for the full list.

---

## Sections

| Page | What it covers |
| --- | --- |
| [Bootstrap](setup/bootstrap.md) | System requirements, what gets installed, skip flags, modes |
| [Managing dotfiles](setup/chezmoi.md) | chezmoi workflow, editing dotfiles, template variables, shared home safety |
| [Package management](setup/packages.md) | Adding tools via cargo, npm, pip, or Homebrew |
| [Day-to-day workflow](usage/updates.md) | Updating, adding packages, editing dotfiles |
| [Troubleshooting](usage/troubleshooting.md) | Tools not found, PATH issues, build failures |
| [Docs and hosting](infra/docs-and-hosting.md) | How this site is built, deployed, and managed |
