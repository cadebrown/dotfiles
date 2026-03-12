# Bootstrap a new machine

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Prompts for name and email once. Everything else runs unattended.

### Skip the prompts

Pre-seed name and email to run fully unattended:

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" \
  curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Values are cached in `~/.config/chezmoi/chezmoi.toml`. On re-runs, they're read from the cache — no prompts.

### From a local clone

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

---

## macOS

### Requirements

| Requirement | How to get it |
|---|---|
| macOS 13+ (Ventura or later) | — |
| Xcode Command Line Tools | Homebrew prompts automatically, or: `xcode-select --install` |
| Internet access | — |

No sudo required.

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
3. **oh-my-zsh** + plugins (pure prompt, autosuggestions, fast-syntax-highlighting, completions)
4. **Homebrew** → `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
5. **All packages** from `packages/Brewfile` — CLI tools, casks, macOS-only apps
   - Includes `rustup` (Homebrew's code-signed build — required for macOS Sequoia+)
6. **Services**: colima registered as a login service (rootless Docker); iTerm2 preferences configured
7. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
8. **Rust** toolchain → `~/.local/$PLAT/rustup/` + `~/.local/$PLAT/cargo/`
   - Uses Homebrew's `rustup` (code-signed), which is required on macOS Sequoia+ where the linker
     enforces `com.apple.provenance` on object files
   - `cargo-binstall` is installed first — downloads pre-built binaries from GitHub releases
     when available, falls back to source compilation otherwise
   - Cargo tools install to `~/.local/$PLAT/cargo/bin/`
9. **Python** via uv → `~/.local/$PLAT/venv/`
10. **Claude Code** via Homebrew cask + plugins + MCP servers

Total time: ~5 minutes on a fast connection (most packages pour as precompiled bottles).

---

## Linux

### Requirements

| Requirement | Notes |
|---|---|
| x86\_64 or aarch64 | — |
| **Docker (rootless)** or **Podman** | Required for the package install step |
| `git` and `curl` | Pre-installed on most systems |
| Internet access | — |

No sudo required after the initial container runtime setup.

### Setting up Docker or Podman

**Rootless Docker** (runs entirely as your user — no root daemon):

```sh
curl -fsSL https://get.docker.com/rootless | sh
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
systemctl --user enable --now docker
```

Docs: [docs.docker.com/engine/security/rootless](https://docs.docker.com/engine/security/rootless/)

**Podman** (rootless by design — no daemon, no sudo):

```sh
apt install podman    # Debian/Ubuntu (may need sudo once)
dnf install podman    # RHEL/Fedora
which podman          # HPC clusters: often pre-installed
```

The bootstrap script checks for `docker` first, then `podman`. Either works.

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
3. **oh-my-zsh** + plugins
4. **Homebrew** → `~/.local/$PLAT/brew/` (inside manylinux_2_28 container; casks skipped)
   - AlmaLinux 8, glibc 2.28; Homebrew bundles its own glibc so binaries are self-contained
   - First run: ~10 min (a few packages compile from source); subsequent runs skip installed items
5. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
6. **Rust** via `sh.rustup.rs` → `~/.local/$PLAT/rustup/` + `~/.local/$PLAT/cargo/`
   - `cargo-binstall` is installed first — downloads pre-built binaries from GitHub releases
     when available, falls back to source compilation otherwise
7. **Python** via uv → `~/.local/$PLAT/venv/`
8. **Claude Code** native binary → `~/.local/$PLAT/bin/claude` + plugins + MCP servers

---

## Skipping steps

Any step can be disabled:

```sh
INSTALL_PACKAGES=0   # skip Homebrew + brew bundle
INSTALL_SERVICES=0   # skip colima/iTerm2 service setup (macOS)
INSTALL_ZSH=0        # skip oh-my-zsh
INSTALL_NODE=0       # skip nvm + Node.js + global npm packages
INSTALL_RUST=0       # skip rustup + cargo tools
INSTALL_PYTHON=0     # skip uv + venv
INSTALL_CLAUDE=0     # skip Claude Code plugins + MCP servers
```

Example — dotfiles only, no runtimes:

```sh
INSTALL_PACKAGES=0 INSTALL_ZSH=0 INSTALL_NODE=0 \
INSTALL_RUST=0 INSTALL_PYTHON=0 INSTALL_CLAUDE=0 \
~/dotfiles/bootstrap.sh
```

---

## Shared home directories

If two machines share a home directory (NFS/GPFS), run `bootstrap.sh` on each independently:

- chezmoi reads the cached config — no re-prompting
- Dotfiles are already applied — no changes
- All compiled tools install to `~/.local/$PLAT/` where `PLAT = $(uname -m)-$(uname -s)`
  (e.g., `aarch64-Linux`, `x86_64-Linux`, `arm64-Darwin`)
- Each machine gets its own arch-specific binaries; text configs are shared freely

Homebrew bottles and rustup ship self-contained binaries — they don't link against the host's system glibc — so different glibc versions on the same arch are not a problem.
