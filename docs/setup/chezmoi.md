# Dotfile Management

[chezmoi](https://chezmoi.io) applies `home/` to `~/`, resolving templates along the way.

## Naming convention

Files in `home/` map to `~/` by chezmoi's naming rules:

- `dot_zshrc` → `~/.zshrc`
- `dot_config/git/ignore` → `~/.config/git/ignore`
- `dot_ssh/config.tmpl` → `~/.ssh/config` (rendered as a template)

The `.tmpl` suffix marks files that contain Go template directives.

## Template variables

```
{{ .name }}              display name (prompted on first run)
{{ .email }}             email (prompted on first run)
{{ .chezmoi.os }}        "darwin" or "linux"
{{ .chezmoi.arch }}      "amd64" or "arm64"
{{ .chezmoi.username }}  system login name (auto-detected)
{{ .chezmoi.homeDir }}   home directory path
```

## Files that tools also write

Some tracked files are mutated by other programs (e.g. `~/.claude/settings.json` is updated by Claude Code on plugin install). chezmoi doesn't auto-apply — drift is safe until you decide what to do:

```sh
chezmoi diff                         # see what changed
chezmoi add ~/.claude/settings.json  # pull live version into source
```
