# Introduction

Personal dotfiles for macOS and Linux, managed with [chezmoi](https://chezmoi.io). Designed for shared home directories across machines with different architectures, and Linux systems without sudo.

## Design constraints

- **Shared home directories** — the same `$HOME` may be NFS-mounted across machines with different arch (e.g. x86_64 and aarch64). Text configs are shared freely; compiled binaries are isolated by `$PLAT = $(uname -m)-$(uname -s)`.
- **No sudo on Linux** — Homebrew compiles inside a rootless container; rustup, uv, and Node install to user-local paths.
- **Idempotent** — every script and `chezmoi apply` is safe to re-run. Running bootstrap on a second machine that shares a home just installs that machine's PLAT-specific tools.
- **glibc portability** — Linux packages install inside a `manylinux_2_28` container (AlmaLinux 8, glibc 2.28). Most pour as precompiled bottles; Homebrew bundles its own glibc so binaries are self-contained.

## PLAT isolation

Every compiled binary lives under `~/.local/$PLAT/`:

| Path | Contents |
|---|---|
| `~/.local/$PLAT/bin/` | chezmoi, uv, uvx |
| `~/.local/$PLAT/brew/` | Homebrew prefix (Linux only) |
| `~/.local/$PLAT/nvm/` | nvm + Node.js versions |
| `~/.local/$PLAT/nix-profile/` | Nix user profile (if Nix installed) |
| `~/.local/$PLAT/rustup/` | Rust toolchain |
| `~/.local/$PLAT/cargo/` | Cargo home (binaries at `cargo/bin/`) |
| `~/.local/$PLAT/venv/` | Python virtualenv |

`~/.local/bin/` stays on PATH for arch-neutral shell scripts only.

The shell profile computes `_PLAT` at login and sets all tool paths from it — so SSH-ing into either machine automatically activates the correct binaries.

## Layout

| Path | Purpose |
|---|---|
| `bootstrap.sh` | Entry point for new machines |
| `.chezmoi.toml.tmpl` | Per-machine prompts (name, email) |
| `home/` | Dotfiles source — applied to `~/` by chezmoi |
| `packages/Brewfile` | Packages for macOS (bottles) and Linux (compiled in container) |
| `install/` | Idempotent install scripts |
| `docs/` | This documentation (built with mdBook) |

## Package management

| Platform | Tool | Notes |
|---|---|---|
| macOS | Homebrew | Native bottles; casks for GUI apps |
| Linux | Homebrew in manylinux_2_28 container | Precompiled bottles; casks skipped |

Same `Brewfile` on both platforms — `if OS.mac?` blocks handle the differences automatically.
