# Bootstrap a new machine

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email once. Everything else runs unattended.

### Skip the prompts

Pre-seed name and email to run fully unattended:

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Values are cached in `~/.config/chezmoi/chezmoi.toml`. On re-runs, they're read from the cache — no prompts.

### From a local clone

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

---

## macOS

### Requirements

| Requirement | How to get it |
|---|---|
| macOS 13+ (Ventura or later) | — |
| Xcode Command Line Tools | Homebrew prompts automatically, or: `xcode-select --install` |
| Internet access | — |

No sudo required.

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
3. **oh-my-zsh** + plugins (pure prompt, autosuggestions, fast-syntax-highlighting, completions)
4. **Homebrew** → `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
   - All packages from `packages/Brewfile` — CLI tools, casks, macOS-only apps
   - Includes `rustup` (Homebrew's code-signed build — required for macOS Sequoia+)
5. **Services**: colima registered as a login service (rootless Docker); iTerm2 preferences configured
6. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
7. **Rust** toolchain → `~/.local/$PLAT/rustup/` + `~/.local/$PLAT/cargo/`
   - Uses Homebrew's `rustup` (code-signed), required on macOS Sequoia+ where the linker
     enforces `com.apple.provenance` on object files
   - `cargo-binstall` downloads pre-built binaries from GitHub releases when available,
     falls back to source compilation otherwise
   - Cargo tools install to `~/.local/$PLAT/cargo/bin/`
8. **Python** via uv → `~/.local/$PLAT/venv/`
9. **Claude Code** via Homebrew cask + plugins + MCP servers

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
3. **oh-my-zsh** + plugins
4. **Homebrew** → `~/.local/$PLAT/brew/`
   - Installs Homebrew's own glibc 2.35 first — binaries are fully self-contained,
     independent of the host system glibc
   - Most packages pour as precompiled bottles; glibc builds from source (~2 min) on first run
5. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
6. **Rust** via `sh.rustup.rs` → `~/.local/$PLAT/rustup/` + `~/.local/$PLAT/cargo/`
   - `cargo-binstall` downloads pre-built binaries from GitHub releases when available,
     falls back to source compilation otherwise
7. **Python** via uv → `~/.local/$PLAT/venv/`
8. **Claude Code** native binary → `~/.local/$PLAT/bin/claude` + plugins + MCP servers

Total time: ~5 minutes on a fast connection.

---

## Skipping steps

Any step can be disabled with an environment variable:

```sh
INSTALL_PACKAGES=0   # skip Homebrew + brew bundle
INSTALL_SERVICES=0   # skip colima/iTerm2 service setup (macOS)
INSTALL_ZSH=0        # skip oh-my-zsh
INSTALL_NODE=0       # skip nvm + Node.js + global npm packages
INSTALL_RUST=0       # skip rustup + cargo tools
INSTALL_PYTHON=0     # skip uv + venv
INSTALL_CLAUDE=0     # skip Claude Code plugins + MCP servers
```

Example — dotfiles only, no runtimes:

```sh
INSTALL_PACKAGES=0 INSTALL_ZSH=0 INSTALL_NODE=0 \
INSTALL_RUST=0 INSTALL_PYTHON=0 INSTALL_CLAUDE=0 \
~/dotfiles/bootstrap.sh
```

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
DOTFILES_SCRATCH_PATH=/scratch/$USER \
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" \
~/dotfiles/bootstrap.sh
```

This symlinks `~/.local` and `~/.cache` to `$DOTFILES_SCRATCH_PATH/.paths/` before any tools are installed, so the multi-GB Homebrew prefix and caches never touch NFS.
