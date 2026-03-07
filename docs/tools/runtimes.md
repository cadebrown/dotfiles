# Runtimes (mise)

[mise](https://mise.jdx.dev) manages language runtime versions. It replaces nvm, pyenv, rbenv, and similar per-language tools with a single unified interface.

## How it works

mise installs runtimes to `~/.local/share/mise/installs/` and shims them into PATH. Versions are specified globally in `packages/mise.toml` and can be overridden per-project with a local `.mise.toml`.

## Installed runtimes

| Runtime | Version | Notes |
|---|---|---|
| Node | LTS | For web tools and scripts |
| Python | 3.12 | Supplemental to `~/.venv` |

Rust is **not** managed by mise — it's handled by rustup directly, which integrates better with the Rust toolchain ecosystem (multiple targets, components, etc).

## Common commands

```sh
# Install all versions declared in mise.toml
mise install

# Use a specific version globally
mise use --global node@20

# Use a specific version in the current project
mise use node@18

# List installed versions
mise list

# Run a command with a specific runtime
mise exec python@3.11 -- python script.py
```

## Per-project overrides

Drop a `.mise.toml` in any project root:

```toml
[tools]
node = "18"
python = "3.11"
```

mise activates it automatically when you enter the directory.
