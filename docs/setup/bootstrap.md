# Bootstrap a new machine

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Or from a clone:

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

No sudo required on either platform. The script detects the OS and runs the right steps.

---

## macOS

### Requirements

| Requirement | How to get it |
|---|---|
| macOS 13+ | — |
| Xcode Command Line Tools | Homebrew prompts automatically, or: `xcode-select --install` |
| Internet access | — |

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply` — prompts for name + email on first run
3. **oh-my-zsh** + plugins (pure prompt, autosuggestions, fast-syntax-highlighting, completions)
4. **Homebrew** → `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
5. **Packages** from `packages/Brewfile` — CLI tools, casks, macOS services
6. **colima** registered as a login service (rootless Docker runtime)
7. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
8. **Rust** via rustup → `~/.local/$PLAT/rustup/`, cargo tools → `~/.local/$PLAT/cargo/`
9. **Python** via uv → `~/.local/$PLAT/venv/`
10. **Claude Code** via Homebrew cask + plugins + MCP servers

---

## Linux

### Requirements

| Requirement | Notes |
|---|---|
| x86\_64 or aarch64 | — |
| **Docker (rootless)** or **Podman** | Required for the package install step. See below. |
| `git` and `curl` | Pre-installed on most systems |
| Internet access | — |

No sudo is needed after the initial Docker/Podman setup. Packages install inside a `manylinux_2_28` container (AlmaLinux 8, glibc 2.28) — most pour as precompiled bottles; Homebrew bundles its own glibc so the binaries are self-contained on any host.

### Docker (rootless)

Rootless Docker runs entirely as your user — no root daemon.

```sh
curl -fsSL https://get.docker.com/rootless | sh
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
systemctl --user enable --now docker
```

Full docs: [docs.docker.com/engine/security/rootless](https://docs.docker.com/engine/security/rootless/)

### Podman (rootless)

Podman is rootless by design — no daemon, no sudo.

```sh
apt install podman    # Debian/Ubuntu (may need sudo once)
dnf install podman    # RHEL/Fedora
which podman          # HPC clusters: often already available
```

The bootstrap script checks for `docker` first, then `podman`. Either works.

### What gets installed

1. **chezmoi** → `~/.local/$PLAT/bin/chezmoi`
2. **Dotfiles** applied via `chezmoi apply`
3. **oh-my-zsh** + plugins
4. **Homebrew** → `~/.local/$PLAT/brew/` (inside manylinux container; casks skipped)
5. **Node.js** via nvm → `~/.local/$PLAT/nvm/`
6. **Rust** via rustup → `~/.local/$PLAT/rustup/`, `~/.local/$PLAT/cargo/`
7. **Python** via uv → `~/.local/$PLAT/venv/`
8. **Claude Code** native binary → `~/.local/$PLAT/bin/claude` + plugins + MCP servers

First run takes ~10 minutes (glibc and a few others compile from source). Subsequent runs skip already-installed packages.

---

## Skipping steps

Any step can be skipped with an environment variable:

```sh
INSTALL_PACKAGES=0   # skip Homebrew + brew bundle
INSTALL_ZSH=0        # skip oh-my-zsh
INSTALL_NODE=0       # skip nvm + Node.js
INSTALL_RUST=0       # skip rustup + cargo tools
INSTALL_PYTHON=0     # skip uv + venv
INSTALL_CLAUDE=0     # skip Claude Code plugins + MCP servers
```

Example — skip everything except dotfiles:

```sh
INSTALL_PACKAGES=0 INSTALL_ZSH=0 INSTALL_NODE=0 \
INSTALL_RUST=0 INSTALL_PYTHON=0 INSTALL_CLAUDE=0 \
~/dotfiles/bootstrap.sh
```

---

## First-run prompts

chezmoi asks for **display name** and **email** once. Values are cached in `~/.config/chezmoi/chezmoi.toml`. To skip the prompts, pre-seed them:

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

To re-prompt (e.g. after changing email): `chezmoi init --data=false`

---

## Shared home directories

If two machines share a home directory (NFS), run `bootstrap.sh` independently on each:

- chezmoi finds the cached config — no prompts the second time
- Dotfiles are already applied — no changes needed
- All tool installs use `~/.local/$PLAT/`, so each machine gets its own arch-specific binaries without conflict

All tools installed here (Homebrew bottles, rustup, uv, nvm) ship self-contained binaries — they don't link against the host glibc — so different glibc versions on the same arch are not a problem.
