# Bootstrap

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Or from a clone: `~/dotfiles/bootstrap.sh`

## Steps

1. Install chezmoi to `~/.local/bin/$PLAT/`
2. Apply dotfiles via chezmoi (prompts for name + email on first run)
3. Install system packages — Homebrew on macOS, Nix on Linux
4. Install Node LTS via nvm → `~/.nvm-$PLAT/`
5. Install Rust toolchain → `~/.rustup-$PLAT/`, `~/.cargo-$PLAT/`
6. Create Python venv → `~/.venv-$PLAT/`
7. Install Claude Code plugins

Where `$PLAT` = `$(uname -m)-$(uname -s)`, e.g. `x86_64-Linux` or `aarch64-Linux`.

## Skipping steps

```sh
INSTALL_NODE=0 INSTALL_RUST=0 INSTALL_PYTHON=0 INSTALL_CLAUDE=0 ~/dotfiles/bootstrap.sh
```

## First-run prompts

chezmoi asks for **display name** and **email** once, caches them in `~/.config/chezmoi/chezmoi.toml`. To re-prompt: `chezmoi init --data=false`.

## Shared home directories

If two machines share a home directory (e.g. NFS), just run `bootstrap.sh` on each machine independently:

- chezmoi finds the cached config in `~/.config/chezmoi/chezmoi.toml` — no prompts
- Dotfiles are already applied — chezmoi detects no changes
- Tool installs are PLAT-specific, so each machine gets its own isolated set

The shell profile reads `$PLAT` at login time and sets all tool paths accordingly, so logging into either machine automatically uses the correct binaries.
