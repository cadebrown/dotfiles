# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Works on macOS (arm64) and Linux (arm64 + x86_64), including shared home directories across distros/machines. No sudo required on Linux.

## Bootstrap

```sh
# One-liner on a new machine
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash

# Or from a cloned repo
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
cd ~/dotfiles && ./bootstrap.sh
```

`bootstrap.sh` will:
1. Install chezmoi to `~/.local/bin/<arch>-<os>/`
2. Apply all dotfiles via chezmoi (prompts for name, email, work machine, etc.)
3. Install packages — Homebrew on macOS, Nix on Linux
4. Install language runtimes via mise
5. Optionally install Rust toolchain and Python venv

All steps are idempotent — safe to re-run.

## Structure

```
dotfiles/
├── bootstrap.sh               # Entry point
├── .chezmoi.toml.tmpl         # Per-machine config (name, email, work flag)
│
├── home/                      # Files managed by chezmoi → applied to ~/
│   ├── dot_zshrc.tmpl         # Interactive shell
│   ├── dot_zprofile.tmpl      # Login shell (PATH, env vars)
│   ├── dot_gitconfig.tmpl     # Git config (templated name/email)
│   ├── dot_gitconfig-work.tmpl
│   ├── dot_aerospace.toml     # AeroSpace window manager (macOS)
│   ├── dot_pythonrc           # Python REPL enhancements
│   ├── dot_ssh/config.tmpl
│   └── dot_config/
│       ├── nvim/              # Neovim (kickstart-based)
│       ├── ghostty/           # Ghostty terminal
│       ├── mise/              # Language runtime versions
│       ├── git/ignore         # Global gitignore
│       ├── linearmouse/       # LinearMouse (macOS)
│       └── claude/            # Claude Code settings + CLAUDE.md
│
├── packages/
│   ├── Brewfile               # macOS packages
│   ├── cargo.txt              # Rust tools (cargo install)
│   ├── pip.txt                # Python packages (uv pip install)
│   ├── mise.toml              # Language runtime versions
│   ├── claude-plugins.txt     # Claude Code plugins
│   └── nix/                   # Nix home-manager (Linux)
│       ├── home.nix
│       └── flake.nix
│
└── install/                   # Idempotent install scripts
    ├── _lib.sh                # Shared helpers (detect_os, log, etc.)
    ├── chezmoi.sh
    ├── homebrew.sh
    ├── nix.sh
    ├── mise.sh
    ├── rust.sh
    ├── python.sh
    └── claude.sh
```

## Day-to-day

```sh
# Pull latest changes and apply
chezmoi update

# Edit a dotfile (opens in $EDITOR, applies on save)
chezmoi edit ~/.zshrc

# Add a new file to chezmoi
chezmoi add ~/.config/foo/bar

# Preview what would change
chezmoi diff

# Sync macOS packages
brew bundle --file=~/dotfiles/packages/Brewfile

# Sync Claude plugins
~/dotfiles/install/claude.sh
```

## Multi-arch / shared home

Compiled binaries go to `~/.local/bin/<arch>-<os>/` — each machine manages its own. Text configs (managed by chezmoi) are fully shared. `chezmoi update` on any machine picks up config changes instantly without touching binaries.

## Adding a new dotfile

```sh
# 1. Let chezmoi take ownership
chezmoi add ~/.config/something/config

# 2. Optionally convert to template for OS-specific sections
chezmoi chattr +template ~/.config/something/config

# 3. Commit
cd ~/dotfiles && git add -A && git commit
```
