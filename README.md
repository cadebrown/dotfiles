# dotfiles

Personal dotfiles for macOS and Linux. One command bootstraps a complete dev environment -- idempotent, safe on shared NFS home directories across CPU architectures. No sudo required on Linux.

Fork this repo and modify for your own setup.

## Bootstrap

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email once (cached in `~/.config/chezmoi/chezmoi.toml`). Re-run anytime to converge -- it installs what's missing, skips what's current.

```sh
# Unattended (CI, shared systems)
DF_NAME="Your Name" DF_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash

# From a local clone
~/dotfiles/bootstrap.sh             # full install
~/dotfiles/bootstrap.sh update      # pull + refresh (no brew upgrade)
~/dotfiles/bootstrap.sh upgrade     # pull + upgrade everything
```

Any step can be skipped with `DF_DO_*=0` env vars (e.g. `DF_DO_RUST=0`).

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

### Languages

| Language | Tool | Install location | Package list |
| --- | --- | --- | --- |
| **Rust** | rustup + cargo-binstall | `$LOCAL_PLAT/rustup/`, `$LOCAL_PLAT/cargo/` | `packages/cargo.txt` |
| **Node.js** | nvm (lazy-loaded in zsh) | `$LOCAL_PLAT/nvm/` | `packages/npm.txt` |
| **Python** | uv + venv | `$LOCAL_PLAT/venv/` | `packages/pip.txt` |

Rust tools are installed via `cargo-binstall` -- pre-built binaries from GitHub releases when available, source compilation as fallback. On macOS, rustup comes from Homebrew (code-signed, required on Sequoia+).

### AI tools

- **Claude Code** -- native binary + plugins (`packages/claude-plugins.txt`) + MCP servers (`packages/claude-mcp.txt`)
- **Codex CLI** -- native binary from GitHub releases

### macOS-specific

- **System settings** (`install/macos-settings.sh`) -- Dock autohide, Finder path bar, fast key repeat, tap to click, PNG screenshots, Safari dev menu, iTerm2 prefs
- **Services** (`install/macos-services.sh`) -- Colima registered as a login service (rootless Docker)

### Auth (opt-in)

`install/auth.sh` creates `~/.{service}.env` files (chmod 600) for `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`. Sourced automatically by all install scripts. Run with `DF_DO_AUTH=1` during bootstrap or standalone.

### Home directories

`install/dirs.sh` creates `~/dev`, `~/bones`, `~/misc` (configurable via `DF_DIRS`). On systems with scratch space, these symlink directly under `$SCRATCH/`.

---

## Philosophy

**macOS** uses Homebrew at `/opt/homebrew` with native bottles. Rust gets Homebrew's code-signed `rustup` (required on Sequoia+). System preferences are set via `defaults write`.

**Linux** uses Homebrew at `~/.local/$PLAT/brew/` -- a custom per-CPU prefix with its own glibc 2.35, so binaries are self-contained. No sudo, no Docker, no container.

### PLAT isolation

Every compiled binary lives under `~/.local/$PLAT/` where `PLAT` is detected from CPU features at shell startup. On a shared NFS home, each machine gets its own isolated binaries. Text configs are shared freely.

```
~/.local/plat_Linux_x86-64-v4/    # AVX-512 (Ice Lake+, Zen 4+)
~/.local/plat_Linux_x86-64-v3/    # AVX2 (Haswell+, Zen 2+)
~/.local/plat_Darwin_arm64/        # Apple Silicon
```

The shell profile detects the current machine's PLAT and puts only that directory's paths on PATH. One home, many machines, no conflicts. Each PLAT also gets CPU-specific compiler flags (`-march=x86-64-v3`, etc.) so tools compiled from source use the best available instructions.

---

## Repo structure

```
dotfiles/
├── bootstrap.sh               # Entry point (install / update / upgrade)
├── home/                      # Dotfiles managed by chezmoi → applied to ~/
│   ├── dot_zshrc.tmpl         # ZSH interactive config
│   ├── dot_zprofile.tmpl      # ZSH login shell (PATH, env, PLAT detection)
│   ├── dot_bashrc.tmpl        # Bash interactive config
│   ├── dot_bash_profile.tmpl  # Bash login shell (mirrors zprofile)
│   ├── dot_gitconfig.tmpl     # Git config
│   ├── dot_claude/            # Claude Code global instructions
│   ├── dot_codex/             # Codex CLI config
│   └── dot_config/            # App configs (nvim, ghostty, git, etc.)
│
├── packages/
│   ├── Brewfile               # Homebrew (macOS + Linux, single file)
│   ├── cargo.txt              # Rust tools (cargo-binstall)
│   ├── pip.txt                # Python packages (uv)
│   ├── npm.txt                # Global npm packages
│   ├── claude-plugins.txt     # Claude Code plugins
│   └── claude-mcp.txt         # Claude Code MCP servers
│
├── install/
│   ├── _lib.sh                # Shared helpers, PLAT detection, all path vars
│   ├── plat/                  # Per-PLAT CPU detection + compiler flags
│   ├── chezmoi.sh             # chezmoi binary
│   ├── zsh.sh                 # oh-my-zsh + plugins
│   ├── homebrew.sh            # macOS: Homebrew + Brewfile
│   ├── linux-packages.sh      # Linux: Homebrew + glibc + Brewfile
│   ├── node.sh, rust.sh, python.sh
│   ├── claude.sh, codex.sh    # AI tool binaries
│   ├── macos-settings.sh      # macOS defaults write
│   ├── macos-services.sh      # macOS launchd services
│   ├── auth.sh                # API token setup
│   ├── dirs.sh                # Home directory structure
│   ├── scratch.sh             # NFS scratch space symlinks
│   └── verify-path.sh         # PATH diagnostic tool
│
├── docs/                      # mdBook → dotfiles.cade.io
├── infra/cloudflare/          # OpenTofu config for Cloudflare Pages
└── tests/                     # Docker-based bats test suite
```

### Key files

- **`install/_lib.sh`** -- every install script sources this first. Defines `PLAT`, `LOCAL_PLAT`, all tool paths, logging functions (`log_okay`/`log_warn`/`log_fail`/`log_debug`), and utilities. This is the central contract.
- **`install/plat/`** -- one subdirectory per platform target. Each has `.plat_check.sh` (exits 0 if this CPU supports it) and `.plat_env.sh` (sets `-march` flags). Detection picks the highest supported level.
- **`home/dot_zprofile.tmpl`** / **`home/dot_bash_profile.tmpl`** -- identical login profiles. PLAT detection, PATH assembly, tool activation. These are the runtime equivalent of `_lib.sh`.

---

## Development

### Edit a dotfile

```sh
chezmoi edit ~/.zshrc              # opens in $EDITOR, applies on save
# or edit source directly:
$EDITOR home/dot_zshrc.tmpl && chezmoi apply
```

### Add a package

```sh
# Rust tool → packages/cargo.txt, then:
bash install/rust.sh

# Homebrew → packages/Brewfile, then:
brew bundle --file=packages/Brewfile

# Python → packages/pip.txt, then:
bash install/python.sh
```

Prefer cargo > npm > pip > Homebrew. Never install the same tool in two layers.

### Add a new install script

1. Create `install/my-thing.sh`, source `_lib.sh` at the top
2. Guard with `has my-thing && { log_okay ...; exit 0; }` for idempotency
3. Add a `DF_DO_MY_THING` flag to `bootstrap.sh`
4. Add tests to `tests/`

### Run tests

```sh
./tests/run.sh    # Docker-based: builds Ubuntu 24.04 image, bootstraps, runs bats
```

### Work on docs

```sh
mdbook serve docs/ --open    # live reload at localhost:3000
```

Every push to `main` auto-deploys to [dotfiles.cade.io](https://dotfiles.cade.io) via Cloudflare Pages.

---

## Docs

Full reference at **[dotfiles.cade.io](https://dotfiles.cade.io)** -- live documentation auto-deployed on every push to `main`. Covers bootstrap details, chezmoi workflow, package management, troubleshooting, and infrastructure.
