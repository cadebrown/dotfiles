# Managing dotfiles

[chezmoi](https://chezmoi.io) manages the files in `home/` and applies them to `~/`, resolving templates along the way.

## The quick version

```sh
chezmoi edit ~/.zshrc          # edit a dotfile (opens in $EDITOR, applies on save)
chezmoi apply                  # apply all pending changes
chezmoi diff                   # preview what would change before applying
chezmoi update                 # git pull + apply (sync from repo)
```

---

## How files map

Files in `home/` map to `~/` by chezmoi's naming rules:

| Source | Target |
|---|---|
| `home/dot_zshrc.tmpl` | `~/.zshrc` |
| `home/dot_config/git/ignore` | `~/.config/git/ignore` |
| `home/dot_ssh/config.tmpl` | `~/.ssh/config` |
| `home/dot_claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |

- `dot_` prefix → `.` in target
- `.tmpl` suffix → rendered as a Go template before writing

---

## Template variables

Use these in any `.tmpl` file:

```
{{ .name }}              display name (prompted on first run)
{{ .email }}             email (prompted on first run)
{{ .chezmoi.os }}        "darwin" or "linux"
{{ .chezmoi.arch }}      "amd64" or "arm64"
{{ .chezmoi.username }}  system login name (auto-detected)
{{ .chezmoi.homeDir }}   home directory path
```

Example — Linux-only alias:

```
{{ if eq .chezmoi.os "linux" -}}
alias open='xdg-open'
{{ end -}}
```

---

## Editing dotfiles

**Via chezmoi** (recommended — auto-applies on save):
```sh
chezmoi edit ~/.zshrc
chezmoi edit ~/.zprofile
```

**Directly in the repo** (then apply manually):
```sh
$EDITOR ~/dotfiles/home/dot_zshrc.tmpl
chezmoi apply
```

Never edit `~/.zshrc` directly — chezmoi will overwrite it on the next apply.

---

## Shared home directory safety

On a shared NFS home, all machines run `chezmoi apply` against the same target files. **Templates must render identically on every machine that shares the home** — otherwise machines overwrite each other on every apply.

**Rule: never use `{{ .chezmoi.arch }}` or any per-machine value in a template.** Arch-specific logic belongs in shell runtime code instead:

```sh
# Good — evaluated at shell startup on each machine independently
export PATH="$HOME/.local/$(uname -m)-$(uname -s)/bin:$PATH"

# Bad — baked into the file at chezmoi apply time; machines fight each other
export PATH="$HOME/.local/{{ .chezmoi.arch }}-{{ .chezmoi.os }}/bin:$PATH"
```

The existing templates only branch on `{{ .chezmoi.os }}` (darwin vs linux), which is stable for all machines sharing a home.

---

## Files that other tools also write

Some tracked files are mutated at runtime. chezmoi won't auto-apply — drift is intentional until you decide what to do:

```sh
chezmoi diff                          # see what changed
chezmoi add ~/.claude/settings.json   # pull the live version back into the repo
```

Notable examples:
- `~/.claude/settings.json` — updated by Claude Code when plugins are installed
- `~/.codex/config.toml` — Codex appends project trust levels at runtime; managed with `create_` prefix so chezmoi writes it once and never overwrites
