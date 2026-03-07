# Shell (zsh)

The shell config is split across two files:

- `~/.zprofile` — login shell: PATH setup, environment variables, tool activation
- `~/.zshrc` — interactive shell: options, prompt, aliases, completions

## PATH order

PATH is built up in `.zprofile` in this order (later entries win for conflicts):

1. `~/.local/bin/<arch>-<os>/` — arch-specific compiled binaries (chezmoi, etc.)
2. `~/.local/bin/` — arch-neutral user binaries
3. Homebrew (macOS) or Nix profile (Linux)
4. `~/.cargo/bin/` — Rust tools
5. mise-managed runtimes (activated via `mise activate zsh`)

The arch-specific prefix (`$(uname -m)-$(uname -s)`) means shared home directories across machines with different architectures work correctly — each machine's compiled binaries are isolated.

## Prompt

[pure](https://github.com/sindresorhus/pure) via oh-my-zsh. Minimal, async git status, shows stash indicator.

## Key aliases

| Alias | Command |
|---|---|
| `g` | `git` |
| `p` | `uv run python` |
| `e` | `vim` |
| `cat` | `bat --paging=never` |
| `datestamp` | `date +"%Y%m%d"` |
| `timestamp` | `date +"%Y%m%d%H%M%S"` |

## oh-my-zsh plugins

| Plugin | Purpose |
|---|---|
| `z` | Jump to frecent directories |
| `git` | Git aliases and completions |
| `direnv` | Per-directory environment variables |
| `colorize` | Syntax-highlighted `cat` |
| `zsh-autosuggestions` | Fish-style history suggestions |
| `fast-syntax-highlighting` | Real-time syntax highlighting |
