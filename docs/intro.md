# Introduction

Personal dotfiles for macOS and Linux, managed with [chezmoi](https://chezmoi.io). Designed for shared home directories across machines with different architectures, and Linux systems without sudo.

## Design constraints

- **Shared home directories** — the same `$HOME` may be mounted across machines with different OS/arch. Text configs are shared freely; compiled binaries are isolated to `~/.local/bin/<arch>-<os>/`.
- **No sudo on Linux** — Nix user mode, mise, rustup, and uv all install to user-local paths.
- **Idempotent** — every script and `chezmoi apply` is safe to re-run.

## Layout

| Path | Purpose |
|---|---|
| `bootstrap.sh` | Entry point for new machines |
| `.chezmoi.toml.tmpl` | Per-machine prompts (name, email) |
| `home/` | Dotfiles source — applied to `~/` by chezmoi |
| `packages/` | Declarative package lists |
| `install/` | Idempotent install scripts |
| `docs/` | This documentation (built with mdBook) |
