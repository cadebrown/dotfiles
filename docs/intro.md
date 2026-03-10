# cade's dotfiles

Personal dotfiles for macOS and Linux — one command sets up a complete, reproducible dev environment on any machine.

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

The name and email are only asked once (or can be pre-seeded as above for unattended installs). Everything else is automatic.

---

## What this gives you

- **One bootstrap command** — installs every tool, dotfile, and language runtime from scratch
- **PLAT isolation** — compiled binaries live under `~/.local/$(uname -m)-$(uname -s)/`, so two machines sharing an NFS home directory never conflict
- **No sudo on Linux** — Homebrew runs inside a rootless container; everything installs to user paths
- **Idempotent** — every script is safe to re-run; running bootstrap on a second machine just installs that machine's arch-specific tools
- **Single source of truth** — one `Brewfile` for both macOS and Linux; `if OS.mac?` blocks handle the differences automatically
- **Fast shell startup** — lazy nvm loading, single `compinit`, ~140ms warm startup

---

## macOS vs Linux

| | macOS | Linux |
|---|---|---|
| Packages | Homebrew (native bottles) | Homebrew in `manylinux_2_28` container |
| Rust toolchain | Homebrew `rustup` (code-signed, required for Sequoia+) | `sh.rustup.rs` |
| Rust tools | `cargo-binstall` (pre-built binaries first, source fallback) | same |
| Services | colima auto-started; iTerm2 prefs configured | — |
| Claude Code | Homebrew cask | Native binary |
| First run | ~5 min | ~10 min |

---

## How it works

[chezmoi](https://chezmoi.io) manages dotfiles as templates in `home/` and applies them to `~/`. The bootstrap script wires everything together:

```
bootstrap.sh
  ↓ chezmoi apply        dotfiles → ~/
  ↓ install/zsh.sh       oh-my-zsh + plugins
  ↓ homebrew.sh          packages from Brewfile (macOS)
    linux-packages.sh    packages from Brewfile (Linux, via container)
  ↓ install/services.sh  colima login service + iTerm2 prefs (macOS)
  ↓ install/node.sh      nvm → Node.js
  ↓ install/rust.sh      rustup → cargo-binstall → cargo tools
  ↓ install/python.sh    uv → Python venv
  ↓ install/claude.sh    Claude Code + plugins + MCP servers
```

Compiled tools land under `~/.local/$PLAT/` — a different directory per arch+OS. A shared home has no conflicts. Text configs (dotfiles) are shared freely; they're arch-neutral by design.

---

## Sections

### Setup — getting started on a new machine

| Page | What it covers |
|---|---|
| [Bootstrap](setup/bootstrap.md) | System requirements, what gets installed, platform-specific steps, skip flags |
| [Managing dotfiles](setup/chezmoi.md) | How chezmoi works, editing dotfiles, template variables |
| [Package management](setup/packages.md) | Adding tools (Homebrew, cargo, npm, pip), why each layer exists |

### Usage — ongoing updates and maintenance

| Page | What it covers |
|---|---|
| [Day-to-day workflow](usage/updates.md) | Adding packages, editing dotfiles, deploying docs, updating tools |
| [Troubleshooting](usage/troubleshooting.md) | Quick reference — when tools aren't found, builds fail, etc. |
