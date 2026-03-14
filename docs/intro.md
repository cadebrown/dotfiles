# cade's dotfiles

Personal dotfiles for macOS and Linux — one command sets up a complete, reproducible dev environment on any machine.

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Name and email are only asked once (or pre-seeded as above for unattended installs). Everything else is automatic.

---

## What this gives you

- **One bootstrap command** — installs every tool, dotfile, and language runtime from scratch
- **Per-CPU isolation** — compiled binaries live under `~/.local/$PLAT/` where `PLAT` is detected from CPU features (e.g. `plat_Linux_x86-64-v4`, `plat_Darwin_arm64`). Two machines sharing an NFS home never conflict.
- **No sudo anywhere** — Homebrew installs to user paths; no container or root daemon needed on Linux
- **Self-contained binaries** — Homebrew installs its own glibc 2.35; binaries don't depend on host system libraries
- **Idempotent** — every script is safe to re-run; running bootstrap on a second machine just installs that machine's tools
- **Single source of truth** — one `Brewfile` for macOS and Linux; `if OS.mac?` blocks handle differences
- **Fast shell startup** — lazy nvm loading (zsh only, via oh-my-zsh plugin), single `compinit`, ~140ms warm startup
- **Both zsh and bash** — identical `.zprofile` and `.bash_profile` templates for consistent environment; bash gets the latest node directly via PATH without nvm lazy loading

---

## macOS vs Linux

| | macOS | Linux |
|---|---|---|
| Packages | Homebrew (native) | Homebrew (native, no container) |
| Rust toolchain | Homebrew `rustup` (code-signed, required for Sequoia+) | `sh.rustup.rs` |
| Rust tools | `cargo-binstall` (pre-built binaries first, source fallback) | same |
| Services | colima auto-started; iTerm2 prefs configured | — |
| Claude Code | Native binary | Native binary |
| First run | ~5 min | ~5 min |

---

## How it works

[chezmoi](https://chezmoi.io) manages dotfiles as templates in `home/` and applies them to `~/`. The bootstrap script wires everything together:

```
bootstrap.sh
  ↓ scratch.sh           redirect ~/.local, ~/.cache to local storage (NFS homes)
  ↓ chezmoi apply        dotfiles → ~/
  ↓ install/zsh.sh       oh-my-zsh + plugins
  ↓ homebrew.sh          packages from Brewfile (macOS)
    linux-packages.sh    glibc + packages from Brewfile (Linux)
  ↓ install/services.sh  colima login service + iTerm2 prefs (macOS)
  ↓ install/node.sh      nvm → Node.js
  ↓ install/rust.sh      rustup → cargo-binstall → cargo tools
  ↓ install/python.sh    uv → Python venv
  ↓ install/claude.sh    Claude Code + plugins + MCP servers
```

Compiled tools land under `~/.local/$PLAT/` — a separate directory per CPU level. On a shared home directory, each machine installs into its own `$PLAT` subdirectory. Text configs are arch-neutral and shared freely.

### CPU-level detection

On Linux x86-64, the bootstrap detects the highest microarchitecture level the CPU supports:

| PLAT | CPU requirement | Typical hardware |
|---|---|---|
| `plat_Linux_x86-64-v4` | AVX-512 | Intel Ice Lake+, AMD Zen 4+ |
| `plat_Linux_x86-64-v3` | AVX2/FMA | Intel Haswell+ (2013+), AMD Zen 2+ (2019+) |
| `plat_Linux_x86-64-v2` | SSE4.2 | Intel Nehalem+ (2008+) |
| `plat_Linux_aarch64` | any AArch64 | Graviton, Ampere, etc. |
| `plat_Darwin_arm64` | Apple Silicon | M1/M2/M3/M4+ |

Each level gets binaries compiled with the appropriate `-march=` flags, so tools use the best available instruction set on each machine.

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
