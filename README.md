# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Works on macOS and Linux with per-CPU-level optimization (x86-64-v2/v3/v4, AArch64, Apple Silicon), including shared NFS home directories across machines — no sudo required anywhere. Supports both **zsh** and **bash** with identical configuration.

## Install

### Quick start

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email once. Everything else is automatic.

### Unattended (CI / shared systems)

```sh
DF_NAME="Your Name" DF_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

### From a local clone

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
DF_NAME="Your Name" DF_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

All steps are idempotent — safe to re-run. On a shared home directory, each machine detects its CPU capabilities and installs to its own `~/.local/$PLAT/` directory (e.g. `plat_Linux_x86-64-v4` for AVX-512, `plat_Linux_x86-64-v3` for AVX2). Text configs are shared; binaries are isolated.

---

## Update / Upgrade

```sh
# Pull latest dotfiles + refresh tools (no reinstall, no brew upgrade)
~/dotfiles/bootstrap.sh update

# Pull + upgrade everything (brew upgrade, cargo upgrade)
~/dotfiles/bootstrap.sh upgrade
```

---

## macOS vs Linux

| | macOS | Linux |
|---|---|---|
| Package manager | Homebrew (native) | Homebrew (native, no container, no sudo) |
| Rust toolchain | Homebrew `rustup` (code-signed) | `sh.rustup.rs` |
| Docker/Podman | Colima (auto-started at login) | Not required |
| Claude Code | Native binary | Native binary |
| First run time | ~5 min | ~5 min |

See [docs/setup/bootstrap.md](docs/setup/bootstrap.md) for full platform details.

---

## Usage

```sh
# Pull and apply latest dotfile changes
chezmoi update

# Edit a dotfile in $EDITOR (applies on save)
chezmoi edit ~/.zshrc

# Preview what would change before applying
chezmoi diff

# Re-run any install script — all are idempotent
bash ~/dotfiles/install/rust.sh
bash ~/dotfiles/install/python.sh
bash ~/dotfiles/install/claude.sh

# Set up API tokens (interactive)
bash ~/dotfiles/install/auth.sh

# Apply macOS system preferences
bash ~/dotfiles/install/macos-settings.sh

# Debug mode — verbose output with timing
DF_DEBUG=1 ~/dotfiles/bootstrap.sh
```

---

## Docs

Full guides at [dotfiles.cade.io](https://dotfiles.cade.io) or locally:

```sh
mdbook serve docs/
```
