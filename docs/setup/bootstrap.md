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

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
   - Shell configs for both **zsh** (`.zprofile`) and **bash** (`.bash_profile`)
   - Both shells do identical PLAT detection and PATH setup
3. **oh-my-zsh** + plugins (pure prompt, autosuggestions, fast-syntax-highlighting, completions)
4. **Homebrew** → `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
   - All packages from `packages/Brewfile` — CLI tools, casks, macOS-only apps
   - Includes `rustup` (Homebrew's code-signed build — required for macOS Sequoia+)
5. **Services**: colima registered as a login service (rootless Docker)
6. **macOS defaults**: Dock, Finder, keyboard, trackpad, screenshots, Safari, iTerm2 preferences
7. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
8. **Rust** toolchain → `~/.local/$PLAT/rustup/` + `~/.local/$PLAT/cargo/`
   - Uses Homebrew's `rustup` (code-signed), required on macOS Sequoia+ where the linker
     enforces `com.apple.provenance` on object files
   - `cargo-binstall` downloads pre-built binaries from GitHub releases when available,
     falls back to source compilation otherwise
   - Cargo tools install to `~/.local/$PLAT/cargo/bin/`
9. **Python** via uv → `~/.local/$PLAT/venv/`
10. **Claude Code** native binary → `~/.local/$PLAT/bin/claude` + plugins + MCP servers
11. **Codex CLI** native binary → `~/.local/$PLAT/bin/codex`

Total time: ~5 minutes on a fast connection (most packages pour as precompiled bottles).

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

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
   - Shell configs for both **zsh** (`.zprofile`) and **bash** (`.bash_profile`)
   - Both shells do identical PLAT detection and PATH setup
3. **oh-my-zsh** + plugins
4. **Homebrew** → `~/.local/$PLAT/brew/` (native install, no Docker/Podman needed)
   - Installs Homebrew's own glibc 2.35 first — binaries are fully self-contained,
     independent of the host system glibc
   - Most packages pour as precompiled bottles; glibc builds from source (~2 min) on first run
   - Custom Python@3.14 patches applied automatically for Linux compatibility
5. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
6. **Rust** via `sh.rustup.rs` → `~/.local/$PLAT/rustup/` + `~/.local/$PLAT/cargo/`
   - `cargo-binstall` downloads pre-built binaries from GitHub releases when available,
     falls back to source compilation otherwise
7. **Python** via uv → `~/.local/$PLAT/venv/`
8. **Claude Code** native binary → `~/.local/$PLAT/bin/claude` + plugins + MCP servers
9. **Codex CLI** native binary → `~/.local/$PLAT/bin/codex`

Total time: ~5 minutes on a fast connection.

---

## Skipping steps

Any step can be disabled with an environment variable:

```sh
DF_DO_SCRATCH=0         # skip scratch space symlink setup
DF_DO_DIRS=0            # skip home directory creation (~/dev, ~/bones, ~/misc)
DF_DO_PACKAGES=0        # skip Homebrew + brew bundle
DF_DO_MACOS_SERVICES=0  # skip colima service setup (macOS)
DF_DO_MACOS_SETTINGS=0  # skip macOS settings (Dock, Finder, keyboard, etc.)
DF_DO_ZSH=0             # skip oh-my-zsh
DF_DO_NODE=0            # skip nvm + Node.js + global npm packages
DF_DO_RUST=0            # skip rustup + cargo tools
DF_DO_PYTHON=0          # skip uv + venv
DF_DO_CLAUDE=0          # skip Claude Code install + plugins + MCP servers
DF_DO_CODEX=0           # skip Codex CLI install
DF_DO_AUTH=1             # run interactive API token setup
DF_BREW_UPGRADE=0       # skip Homebrew upgrades (macOS default: 1, Linux default: 0)
```

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

Run `bootstrap.sh` on each machine independently:

- chezmoi reads the cached config — no re-prompting
- Dotfiles are already applied — no changes
- Each machine detects its CPU level and installs compiled tools to its own `~/.local/$PLAT/` directory:

| Machine | PLAT | Where tools live |
|---|---|---|
| AVX-512 Linux (e.g. Ice Lake) | `plat_Linux_x86-64-v4` | `~/.local/plat_Linux_x86-64-v4/` |
| AVX2 Linux (e.g. Haswell/Zen2) | `plat_Linux_x86-64-v3` | `~/.local/plat_Linux_x86-64-v3/` |
| ARM Linux | `plat_Linux_aarch64` | `~/.local/plat_Linux_aarch64/` |
| Apple Silicon | `plat_Darwin_arm64` | `~/.local/plat_Darwin_arm64/` |

Text configs (dotfiles) are arch-neutral and shared freely across all machines.

### Scratch space (large quota environments)

If your home directory has a small quota (common on HPC NFS mounts), direct large directories to local scratch storage:

```sh
DF_SCRATCH=/scratch/$USER \
DF_NAME="Your Name" DF_EMAIL="you@example.com" \
~/dotfiles/bootstrap.sh
```

This symlinks `~/.local` and `~/.cache` to `$DF_SCRATCH/.paths/` before any tools are installed, so the multi-GB Homebrew prefix and caches never touch NFS.

---

## Auth (API tokens)

Set up API tokens interactively:

```sh
bash ~/dotfiles/install/auth.sh

# Or during bootstrap:
DF_DO_AUTH=1 ~/dotfiles/bootstrap.sh
```

Guides you through setting up `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, and `OPENAI_API_KEY`. Creates `~/.{service}.env` files (chmod 600) that are sourced automatically by all install scripts.
