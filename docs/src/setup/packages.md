# Packages

Package management is split by platform and purpose. Each layer is declared in a text file and applied by a script in `install/`.

## Overview

| Layer | File | Script | Platform |
|---|---|---|---|
| System packages | `packages/Brewfile` | `install/homebrew.sh` | macOS |
| System packages | `packages/nix/home.nix` | `install/nix.sh` | Linux |
| Language runtimes | `packages/mise.toml` | `install/mise.sh` | All |
| Rust tools | `packages/cargo.txt` | `install/rust.sh` | All |
| Python packages | `packages/pip.txt` | `install/python.sh` | All |
| Claude plugins | `packages/claude-plugins.txt` | `install/claude.sh` | All |

## Homebrew (macOS)

`packages/Brewfile` declares all macOS packages declaratively. To apply:

```sh
brew bundle --file=~/dotfiles/packages/Brewfile
# or
~/dotfiles/install/homebrew.sh
```

## Nix (Linux)

`packages/nix/home.nix` declares Linux packages via home-manager. No sudo required — Nix installs entirely into `~/.nix-profile`.

```sh
~/dotfiles/install/nix.sh
```

## mise (language runtimes)

[mise](https://mise.jdx.dev) manages language runtime versions (Node, Python, etc.) without sudo. Versions are pinned in `packages/mise.toml`.

```sh
mise install        # install all declared versions
mise use node@lts   # set a version locally
```

## Rust tools

`packages/cargo.txt` lists tools installed via `cargo install`. The install script skips already-installed tools to avoid redundant recompiles.

```sh
~/dotfiles/install/rust.sh
```

To add a tool: append its crate name to `cargo.txt` and re-run the script.

## Python

All Python work happens inside `~/.venv`, activated automatically by `.zprofile`. The venv is created by uv and packages come from `packages/pip.txt`.

```sh
~/dotfiles/install/python.sh

# Install something new
uv pip install <pkg>

# Add it permanently
echo "<pkg>" >> ~/dotfiles/packages/pip.txt
```
