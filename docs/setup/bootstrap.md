# Bootstrap

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Or from a clone:

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

No sudo is required on either platform.

---

## macOS

### System requirements

| Requirement | How to get it |
|---|---|
| macOS 13+ (Ventura) | — |
| Xcode Command Line Tools | Homebrew installer prompts automatically, or: `xcode-select --install` |
| Internet access | — |

That's it. The bootstrap script installs everything else (Homebrew, tools, language runtimes) to user-local paths without sudo.

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
3. **oh-my-zsh + plugins** (pure, autosuggestions, fast-syntax-highlighting, completions)
4. **Homebrew** → `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
   — pulls precompiled bottles; installs all CLI tools and casks from `packages/Brewfile`
5. **colima** started as a login service (Docker-compatible container runtime)
6. **Node.js** (nvm) → `~/.local/$PLAT/nvm/`
7. **Rust toolchain** → `~/.local/$PLAT/rustup/`, `~/.local/$PLAT/cargo/`
8. **Python** (uv + venv) → `~/.local/$PLAT/venv/`
9. **Claude Code plugins**

---

## Linux

### System requirements

| Requirement | Notes |
|---|---|
| Linux x86\_64 or aarch64 | — |
| **Docker (rootless)** or **Podman** | No sudo. See below. |
| `git` and `curl` | For the initial `curl \| bash` bootstrap |
| Internet access | — |
| C compiler (`gcc`, `make`) | Usually pre-installed; needed by Homebrew for source builds |

No sudo is required. Docker/Podman are used to compile packages inside a
`manylinux_2_17` container (glibc 2.17, CentOS 7), so binaries work on any
Linux since ~2014 regardless of distro.

### Installing Docker (rootless)

Rootless Docker runs entirely as your user — no daemon running as root, no
sudo required after setup.

```sh
# Install the rootless setup tool (may need one-time sudo for the tool itself)
curl -fsSL https://get.docker.com/rootless | sh

# Add to your shell profile (bootstrap handles this automatically afterwards)
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"

# Start the daemon
systemctl --user start docker
systemctl --user enable docker   # auto-start at login
```

Full docs: https://docs.docker.com/engine/security/rootless/

### Installing Podman (rootless)

Podman is rootless by design — no daemon, no sudo.

```sh
# Debian/Ubuntu
apt install podman       # may need sudo for this one-time install

# RHEL/Fedora/Rocky
dnf install podman

# On HPC clusters: check if Podman is already available
which podman
```

Podman is a drop-in Docker replacement; the bootstrap script detects and
uses whichever is available (`docker` checked first, then `podman`).

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
3. **oh-my-zsh + plugins**
4. **Homebrew** → `~/.local/$PLAT/brew/`
   — compiled from source inside a `manylinux_2_17` container (glibc 2.17);
     casks and macOS-specific tools are skipped automatically via `if OS.mac?` blocks
5. **Node.js** (nvm) → `~/.local/$PLAT/nvm/`
6. **Rust toolchain** → `~/.local/$PLAT/rustup/`, `~/.local/$PLAT/cargo/`
7. **Python** (uv + venv) → `~/.local/$PLAT/venv/`
8. **Claude Code plugins**

First bootstrap compiles packages from source — expect 30–60 minutes depending
on machine speed and package count. Subsequent runs skip already-installed packages.

---

## Skipping steps

```sh
INSTALL_ZSH=0 INSTALL_PACKAGES=0 INSTALL_NODE=0 \
INSTALL_RUST=0 INSTALL_PYTHON=0 INSTALL_CLAUDE=0 \
~/dotfiles/bootstrap.sh
```

## First-run prompts

chezmoi asks for **display name** and **email** once, caches them in
`~/.config/chezmoi/chezmoi.toml`. To re-prompt: `chezmoi init --data=false`.

## Shared home directories

If two machines share a home directory (e.g. NFS), run `bootstrap.sh` on each
machine independently:

- chezmoi finds the cached config — no prompts
- Dotfiles are already applied — no changes
- All tool installs are PLAT-specific (`~/.local/$PLAT/`), so each machine
  compiles and installs its own binaries independently

On Linux, if two machines share a home but have **different glibc versions**,
they need different PLAT identifiers. By default `$PLAT = $(uname -m)-$(uname -s)`
which only distinguishes arch and OS. If needed, override before running bootstrap:

```sh
PLAT="x86_64-Linux-glibc2.17" ~/dotfiles/bootstrap.sh
```
