# Dotfile Management (chezmoi)

[chezmoi](https://chezmoi.io) manages everything in `~/` that belongs to the dotfiles repo. It works by keeping a source directory (`~/dotfiles/home/`) and applying it to the real home directory, resolving templates along the way.

## Source layout

Files in `home/` map to `~/` with a naming convention:

| Source name | Target |
|---|---|
| `dot_zshrc` | `~/.zshrc` |
| `dot_config/git/ignore` | `~/.config/git/ignore` |
| `dot_ssh/config.tmpl` | `~/.ssh/config` |

The `.tmpl` suffix means the file is a Go template — chezmoi renders it before writing.

## Templates

Templates use built-in chezmoi variables and per-machine data collected on first run:

```
{{ .name }}              → display name (e.g. "Cade Brown")
{{ .email }}             → email address
{{ .chezmoi.os }}        → "darwin" or "linux"
{{ .chezmoi.arch }}      → "amd64" or "arm64"
{{ .chezmoi.username }}  → system login name
{{ .chezmoi.homeDir }}   → e.g. /Users/cade
```

Example — an OS-conditional block in `dot_zshrc.tmpl`:

```sh
{{ if eq .chezmoi.os "darwin" -}}
# macOS-only config
open() { command open "$@"; }
{{ else -}}
# Linux-only config
alias open='xdg-open'
{{ end -}}
```

## Common commands

```sh
# Pull repo changes and apply
chezmoi update

# Edit a managed file (opens $EDITOR, applies on save)
chezmoi edit ~/.zshrc

# See what chezmoi would change
chezmoi diff

# Add a new file to chezmoi management
chezmoi add ~/.config/foo/bar

# Convert a plain file to a template
chezmoi chattr +template ~/.config/foo/bar

# Pull live changes back into the source (e.g. after a tool mutates a file)
chezmoi add ~/.claude/settings.json

# Apply without pulling (use what's already in source)
chezmoi apply
```

## Tracked files that tools also write

Some files chezmoi tracks are also mutated by other tools (e.g. `~/.claude/settings.json` is written by Claude Code on plugin install). The workflow for these:

1. `chezmoi diff` — see what drifted
2. `chezmoi add <file>` — pull the live version back into source
3. Commit the change
