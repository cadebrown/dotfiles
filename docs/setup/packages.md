# Packages

Each layer has a declarative text file and an idempotent install script.

| Layer | File | Platform |
|---|---|---|
| System packages | `packages/Brewfile` | macOS |
| System packages | `packages/nix/home.nix` | Linux |
| Node | nvm (install/node.sh) | All |
| Rust tools | `packages/cargo.txt` | All |
| Python packages | `packages/pip.txt` | All |
| Claude plugins | `packages/claude-plugins.txt` | All |

## Why this split

- **Homebrew vs Nix** — Homebrew on macOS (familiar, cask support for GUI apps); Nix on Linux (no sudo, multi-arch, reproducible).
- **nvm for Node** — simple, widely understood, installs to `~/.nvm`. No abstraction layer between you and the runtime.
- **rustup for Rust** — handles toolchain components, cross-compilation targets, and `rust-analyzer` directly.
- **`~/.venv` for Python** — a single activated venv for interactive/scripting use. Project-specific envs are handled by uv separately.

## Adding packages

Append to the relevant file and re-run the corresponding script — all scripts skip already-installed items.
