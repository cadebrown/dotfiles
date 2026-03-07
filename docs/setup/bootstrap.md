# Bootstrap

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
```

Or from a clone: `~/dotfiles/bootstrap.sh`

## Steps

1. Install chezmoi to `~/.local/bin/<arch>-<os>/`
2. Apply dotfiles via chezmoi (prompts for name + email on first run)
3. Install system packages — Homebrew on macOS, Nix on Linux
4. Install language runtimes via mise
5. Install Rust toolchain + `cargo.txt` tools
6. Create `~/.venv` via uv, install `pip.txt` packages
7. Install Claude Code plugins

## Skipping steps

```sh
INSTALL_RUST=0 INSTALL_PYTHON=0 INSTALL_CLAUDE=0 ~/dotfiles/bootstrap.sh
```

## First-run prompts

chezmoi asks for **display name** and **email** once, caches them in `~/.config/chezmoi/chezmoi.toml`. To re-prompt: `chezmoi init --data=false`.

Enter personal or work email as appropriate — there's no separate work/personal split, just one identity per machine.
