# cade's dotfiles

Personal dotfiles for macOS and Linux. One command bootstraps a complete dev environment — idempotent, no sudo on Linux, and (optionally) safe on shared NFS home directories across CPU architectures.

```sh
DF_NAME="Your Name" DF_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

`DF_NAME` / `DF_EMAIL` are needed when piping into `bash` (the pipe occupies stdin, so chezmoi can't prompt); from a local clone, `~/dotfiles/bootstrap.sh` prompts interactively. Re-run anytime to converge.

**Pick your path:**

| Goal | Page |
| --- | --- |
| Set up a brand-new machine | [Bootstrap](setup/bootstrap.md) |
| Sync the latest changes | [Day-to-day workflow](usage/updates.md) |
| Add or remove a tool | [Package management](setup/packages.md) |
| Understand PLAT isolation | [PLAT isolation](setup/plat.md) |
| Set up API tokens | [Auth](setup/auth.md) |
| Create a private extension | [Overlays](setup/overlays.md) |
| Look up a `DF_*` flag | [Env-var reference](reference/env-vars.md) |
| Trace what `bootstrap.sh` actually does | [Bootstrap flow](reference/bootstrap-flow.md) |

---

## What gets installed

### Dotfiles and shell

[chezmoi](https://chezmoi.io) manages dotfiles as templates in `home/` and applies them to `~/`. Both **zsh** and **bash** get identical login profiles with PLAT detection, PATH setup, and tool activation.

- **zsh**: oh-my-zsh with [pure](https://github.com/sindresorhus/pure) prompt, autosuggestions, fast-syntax-highlighting, completions, and lazy nvm loading (~140ms startup)
- **bash**: minimal config with git branch prompt, shared aliases, zoxide, fzf completions
- **git**: global config with name/email from chezmoi data, delta as pager
- **SSH**: templated config from `home/dot_ssh/config.tmpl`

### Packages

A single `packages/Brewfile` drives both platforms. On macOS, Homebrew installs native bottles plus casks (GUI apps). On Linux, Homebrew installs to a custom prefix (`$_LOCAL_PLAT/brew/`) with its own glibc — fully self-contained, no sudo.

`if OS.mac?` blocks in the Brewfile handle macOS-only casks and tools; Linux skips them silently.

### Languages

| Language | Tool | Install location | Package list |
| --- | --- | --- | --- |
| **Rust** | rustup + cargo-binstall | `$LOCAL_PLAT/rustup/`, `$LOCAL_PLAT/cargo/` | `packages/cargo.txt` |
| **Node.js** | nvm (lazy-loaded in zsh) | `$LOCAL_PLAT/nvm/` | `packages/npm.txt` |
| **Python** | uv tool install (per CLI tool) | `$LOCAL_PLAT/uv/tools/`, entrypoints in `$LOCAL_PLAT/bin/` | `packages/pip.txt` |

Rust tools install via `cargo-binstall` (downloads pre-built binaries from GitHub releases when available, falls back to source). Python CLI tools each get their own isolated venv via `uv tool install` — no monolithic user-level environment. On macOS, rustup comes from Homebrew (code-signed, required on Sequoia+ where the linker enforces provenance).

### AI tools

- **Claude Code** — native binary from Anthropic's release bucket, plus plugins (`packages/claude-plugins.txt`) and MCP servers (`packages/mcp-servers.txt`)
- **Codex CLI** — npm-installed binary (`@openai/codex` in `npm.txt`), with managed config + hooks under `home/dot_codex/` and `[mcp_servers.*]` blocks generated from the shared `packages/mcp-servers.txt`
- **Cursor / VS Code** — extension lists in `packages/{cursor,vscode}-extensions.txt`; Cursor settings symlinked from `home/dot_cursor/`

### macOS-specific

- **System settings** (`install/macos-settings.sh`) — Dock autohide, Finder extensions/path bar, fast key repeat, tap to click, PNG screenshots, Safari dev menu, iTerm2 prefs
- **Services** (`install/macos-services.sh`) — optional auto-start for Colima (rootless Docker), Ollama, and mlxserve; off by default (`DF_START_LOCAL_SERVICES=1` to enable). Docker CLI plugins always linked.
- **Quick Actions** (`install/macos-quick-actions.sh`) — Finder right-click "Open in Cursor" and friends

### Auth (opt-in)

[`install/auth.sh`](setup/auth.md) is a guided service-registry helper that creates `~/.<service>.env` files (chmod 600) for **GitHub**, **Anthropic**, **OpenAI**, **Cloudflare**, and **HuggingFace** — plus a separate `gh auth login` flow for the Claude GitHub MCP. Sourced automatically by all install scripts and login shells. Run during bootstrap with `DF_DO_AUTH=1` or standalone anytime.

### Home directories

`install/dirs.sh` creates `~/dev`, `~/bones`, and `~/misc` (configurable via `DF_DIRS`). On systems with scratch space, these become symlinks directly under `$SCRATCH/` for fast local storage. See [Scratch space](setup/scratch.md).

---

## PLAT isolation (optional)

By default `$LOCAL_PLAT = $HOME/.local` and everything lives under a flat `~/.local/`. **PLAT isolation is opt-in** — set `DF_USE_PLAT=1` (or `use_plat = true` in chezmoi data) and `$LOCAL_PLAT` becomes `~/.local/$PLAT/`. The point: on a shared NFS home, each machine installs into its own PLAT directory; one home directory, many machines, no conflicts. Single-machine users get the simpler flat layout without the per-PLAT directory tax.

```
DF_USE_PLAT=0  (default, flat)        DF_USE_PLAT=1  (NFS-shared homes)
─────────────────────────────         ───────────────────────────────────
~/.local/                             ~/.local/
├── bin/                              ├── plat_Darwin_arm64/
│   ├── chezmoi                       │   ├── bin/{chezmoi,uv,claude}
│   ├── uv                            │   ├── brew/        (Apple Silicon)
│   └── claude                        │   ├── cargo/bin/   (arm64 binaries)
├── brew/        (one prefix)         │   └── nvm/         (arm64 node)
├── cargo/bin/   (host arch)          ├── plat_Linux_x86-64-v3/
└── nvm/                              │   ├── brew/        (AVX2 glibc)
                                      │   └── ...
$_LOCAL_PLAT = ~/.local                └── plat_Linux_x86-64-v4/  (AVX-512)
                                          └── ...

                                      $_LOCAL_PLAT = ~/.local/$_PLAT
                                      (set per-shell from CPU detection)
```

Capability detection still runs in flat mode — `.plat_env.sh` tunes compiler flags (`-march=x86-64-v3`, `RUSTFLAGS=-Ctarget-cpu=apple-m1`, etc.) for the host CPU even when directory isolation is off. See [PLAT isolation](setup/plat.md) for the decision matrix.

---

## macOS vs Linux

| | macOS | Linux |
| --- | --- | --- |
| Packages | Homebrew at `/opt/homebrew` | Homebrew at `~/.local/$PLAT/brew/` (custom prefix, bundled glibc) |
| Rust | Homebrew `rustup` (code-signed for Sequoia) | `sh.rustup.rs` |
| System settings | Dock, Finder, keyboard, trackpad, Safari, iTerm2 | -- |
| Services | Colima (rootless Docker) | -- |
| sudo required | Yes (Homebrew installer) | No |

---

## Bootstrap modes

```sh
bootstrap.sh              # install (default) — full idempotent setup
bootstrap.sh update       # git pull + chezmoi apply + refresh tools
bootstrap.sh upgrade      # update + brew upgrade + cargo upgrade
```

Any step can be skipped with `DF_DO_*=0` env vars. See [Bootstrap](setup/bootstrap.md) for the full list.

---

## Sections

**Setup**

| Page | What it covers |
| --- | --- |
| [Bootstrap](setup/bootstrap.md) | System requirements, what gets installed, skip flags, modes |
| [Managing dotfiles](setup/chezmoi.md) | chezmoi workflow, editing dotfiles, template variables, shared-home safety |
| [Package management](setup/packages.md) | Adding tools via cargo, npm, pip, or Homebrew |
| [PLAT isolation](setup/plat.md) | When to use it, layouts compared, decommissioning |
| [Auth](setup/auth.md) | Service registry, env-file flow, gh-derive trick |
| [Scratch space](setup/scratch.md) | Symlink topology for NFS-quota relief |
| [Overlays](setup/overlays.md) | Private extension repos (`dotfiles-*/`) |

**Usage**

| Page | What it covers |
| --- | --- |
| [Day-to-day workflow](usage/updates.md) | Updating, adding packages, editing dotfiles |
| [AeroSpace window management](usage/aerospace.md) | Tiling WM keymap (macOS) |
| [Local AI coding](usage/local-llm.md) | Ollama, mlx-lm, opencode, pi setup |
| [Troubleshooting](usage/troubleshooting.md) | Tools not found, PATH issues, build failures |

**Reference**

| Page | What it covers |
| --- | --- |
| [Env vars (`DF_*`)](reference/env-vars.md) | Complete table of every flag and behavior var |
| [Bootstrap flow](reference/bootstrap-flow.md) | Step-by-step diagram of what `bootstrap.sh` does |

**Infrastructure**

| Page | What it covers |
| --- | --- |
| [Docs and hosting](infra/docs-and-hosting.md) | How this site is built, deployed, and managed |
