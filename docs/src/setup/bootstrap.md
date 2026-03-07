# Bootstrap

The bootstrap process takes a machine from zero to fully configured in one command. Every step is idempotent — safe to re-run after partial failures or to update an existing install.

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

If you already have the repo cloned:

```sh
~/dotfiles/bootstrap.sh
```

## What it does

1. **Installs chezmoi** to `~/.local/bin/<arch>-<os>/` (no sudo, arch-specific)
2. **Applies dotfiles** — prompts for display name and email on first run, then applies all templates
3. **Installs packages** — Homebrew on macOS, Nix on Linux
4. **Installs language runtimes** via mise (Node LTS, Python 3.12)
5. **Installs Rust toolchain** via rustup and tools from `cargo.txt`
6. **Creates `~/.venv`** via uv and installs packages from `pip.txt`
7. **Installs Claude Code plugins** from `claude-plugins.txt`

## Environment variables

Any step can be skipped:

```sh
INSTALL_RUST=0 INSTALL_PYTHON=0 ~/dotfiles/bootstrap.sh
```

| Variable | Default | Effect |
|---|---|---|
| `INSTALL_RUST` | `1` | Set to `0` to skip Rust + cargo tools |
| `INSTALL_PYTHON` | `1` | Set to `0` to skip uv + `~/.venv` |
| `INSTALL_CLAUDE` | `1` | Set to `0` to skip Claude plugin install |
| `GITHUB_REPO` | `cadebrown/dotfiles` | Override the source repo |

## First-run prompts

On a fresh machine, chezmoi will ask:

- **Display name** — used in git config (`user.name`)
- **Email** — used in git config (`user.email`); enter personal or work email as appropriate

These are cached in `~/.config/chezmoi/chezmoi.toml` and never asked again. To reset:

```sh
chezmoi init --data=false
```
