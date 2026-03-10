# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Works on macOS (arm64) and Linux (arm64 + x86_64), including shared home directories across machines with no sudo required on Linux.

## Install

### Quick start — no repo needed

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email on first run. Everything else is automatic.

### With name/email pre-seeded (unattended)

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

### From a local clone

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

All steps are idempotent — safe to re-run. On a machine sharing a home directory, re-running just installs that machine's arch-specific binaries under `~/.local/$PLAT/`.

---

## macOS vs Linux

| | macOS | Linux |
|---|---|---|
| Package manager | Homebrew (native bottles) | Homebrew in `manylinux_2_28` container |
| Rust toolchain | Homebrew `rustup` (code-signed) | `sh.rustup.rs` |
| Docker/Podman | Colima (auto-started at login) | Required pre-requisite for packages |
| Claude Code | Homebrew cask | Native binary |
| First run time | ~5 min | ~10 min (some packages compile) |

See [docs/setup/bootstrap.md](docs/setup/bootstrap.md) for full platform requirements.

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

# Sync packages
brew bundle --file=~/dotfiles/packages/Brewfile
```

---

## Docs

Full guides at [dotfiles.cade.io](https://dotfiles.cade.io) or locally:

```sh
mdbook serve docs/
```
