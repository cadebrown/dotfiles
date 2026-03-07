# Introduction

This is the documentation for my personal machine setup. It covers how everything is structured, why certain tools were chosen, and how to reproduce the setup on a new machine.

The dotfiles repo lives at `~/dotfiles` and is managed with [chezmoi](https://chezmoi.io). Configuration files are templates — they adapt to the current OS, architecture, and the name/email entered on first bootstrap.

## Philosophy

- **No sudo on Linux.** All tools install to user-local paths.
- **Shared home directories work.** Arch-specific binaries go to `~/.local/bin/<arch>-<os>/`; text configs are fully shared.
- **Idempotent bootstrap.** Running `bootstrap.sh` twice changes nothing if everything is already in place.
- **One source of truth.** Packages, plugins, and tools are declared in text files (`Brewfile`, `cargo.txt`, `pip.txt`, etc.) and applied by scripts.

## Quick start

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

See [Bootstrap](setup/bootstrap.md) for a full walkthrough.
