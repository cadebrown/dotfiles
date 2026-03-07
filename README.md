# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Works on macOS (arm64) and Linux (arm64 + x86_64), including shared home directories across machines. No sudo required on Linux.

## Bootstrap

```sh
# New machine — no repo needed
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash

# Or from a clone
git clone https://github.com/cadebrown/dotfiles ~/dotfiles && ~/dotfiles/bootstrap.sh
```

Prompts for name and email on first run, then installs chezmoi, applies dotfiles, and sets up packages. All steps are idempotent — run it on each machine that shares a home directory to get PLAT-specific tool installs (`x86_64-Linux`, `aarch64-Linux`, etc.).

## Usage

```sh
# Apply latest changes from the repo
chezmoi update

# Edit a dotfile in $EDITOR, applies on save
chezmoi edit ~/.zshrc

# Add a new file under chezmoi management
chezmoi add ~/.config/foo/bar

# Make a file template (for OS-specific blocks)
chezmoi chattr +template ~/.config/foo/bar

# Preview what would change before applying
chezmoi diff

# Sync macOS packages
brew bundle --file=~/dotfiles/packages/Brewfile

# Re-run any install script (all are idempotent)
~/dotfiles/install/rust.sh
~/dotfiles/install/python.sh
~/dotfiles/install/claude.sh
```

## Docs

Guides, setup notes, and walkthroughs live in [`docs/`](docs/).

```sh
# Browse locally
cargo install mdbook
mdbook serve docs/
```
