# Introduction

Personal dotfiles for macOS and Linux, managed with [chezmoi](https://chezmoi.io). Designed for shared home directories across machines with different architectures, and Linux systems without sudo.

## Design constraints

- **Shared home directories** — the same `$HOME` may be NFS-mounted across machines with different arch (e.g. x86_64 and aarch64). Text configs are shared freely; compiled binaries are isolated by `$PLAT = $(uname -m)-$(uname -s)`.
- **No sudo on Linux** — Nix user mode, rustup, nvm, and uv all install to user-local paths.
- **Idempotent** — every script and `chezmoi apply` is safe to re-run. Running bootstrap on a second machine that shares a home just installs that machine's PLAT-specific tools.

## PLAT isolation

Every compiled binary path is suffixed with `$PLAT`:

| Path | Contents |
|---|---|
| `~/.local/bin/$PLAT/` | chezmoi and other compiled tools |
| `~/.nvm-$PLAT/` | Node (nvm) |
| `~/.rustup-$PLAT/` | Rust toolchain |
| `~/.cargo-$PLAT/` | Rust binaries |
| `~/.venv-$PLAT/` | Python virtualenv |

The shell profile computes `_PLAT` at login and sets all tool paths from it — so SSH-ing into either machine automatically activates the correct binaries.

## Layout

| Path | Purpose |
|---|---|
| `bootstrap.sh` | Entry point for new machines |
| `.chezmoi.toml.tmpl` | Per-machine prompts (name, email) |
| `home/` | Dotfiles source — applied to `~/` by chezmoi |
| `packages/` | Declarative package lists |
| `install/` | Idempotent install scripts |
| `docs/` | This documentation (built with mdBook) |
