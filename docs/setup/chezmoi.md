# Managing dotfiles

[chezmoi](https://chezmoi.io) manages the files in `home/` and applies them to `~/`, resolving templates along the way.

## Data flow

```mermaid
sequenceDiagram
    participant U as User
    participant B as bootstrap.sh
    participant CZ as chezmoi
    participant T as ~/.config/chezmoi/<br/>chezmoi.toml
    participant S as home/dot_X.tmpl<br/>(repo source)
    participant H as ~/.X<br/>(target)
    U->>B: run bootstrap.sh
    B->>CZ: chezmoi init (first run only)
    CZ->>U: prompt name + email (needs a TTY; skipped if DF_NAME / DF_EMAIL pre-set)
    U-->>CZ: "Cade", "brown.cade@..."
    CZ->>T: cache values
    B->>CZ: chezmoi apply
    CZ->>T: read .name, .email, .use_plat
    CZ->>S: read template
    Note over CZ: render Go template — {{ .name }} expands,<br/>{{ if eq .chezmoi.os "linux" }} branches, etc.
    CZ->>H: write rendered file (overwrites!)
    Note over H: never edit ~/.X directly —<br/>next apply overwrites it
```

Templates render at **apply time** using the values in `~/.config/chezmoi/chezmoi.toml`. The prompt only fires if a value is missing — re-runs read from cache.

## The quick version

```sh
chezmoi edit ~/.zshrc          # edit a dotfile (opens in $EDITOR, applies on save)
chezmoi edit ~/.zprofile       # zsh login shell config
chezmoi edit ~/.bash_profile   # bash login shell config (mirrors .zprofile)
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
| `home/dot_zprofile.tmpl` | `~/.zprofile` (zsh login shell) |
| `home/dot_bash_profile.tmpl` | `~/.bash_profile` (bash login shell) |
| `home/dot_config/git/ignore` | `~/.config/git/ignore` |
| `home/dot_ssh/config.tmpl` | `~/.ssh/config` |
| `home/dot_claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `home/dot_codex/AGENTS.md` | `~/.codex/AGENTS.md` |

- `dot_` prefix → `.` in target
- `.tmpl` suffix → rendered as a Go template before writing

---

## Template variables

Use these in any `.tmpl` file:

```text
{{ .name }}              display name (prompted on first run)
{{ .email }}             email (prompted on first run)
{{ .use_plat }}          PLAT directory isolation flag (default false; see PLAT page)
{{ .chezmoi.os }}        "darwin" or "linux"
{{ .chezmoi.arch }}      "amd64" or "arm64"  ← do NOT use in shared-NFS templates
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
chezmoi edit ~/.zprofile       # zsh login shell
chezmoi edit ~/.bash_profile   # bash login shell
```

**Directly in the repo** (then apply manually):
```sh
$EDITOR ~/dotfiles/home/dot_zshrc.tmpl
$EDITOR ~/dotfiles/home/dot_zprofile.tmpl
$EDITOR ~/dotfiles/home/dot_bash_profile.tmpl
chezmoi apply
```

Never edit `~/.zshrc`, `~/.zprofile`, or `~/.bash_profile` directly — chezmoi will overwrite them on the next apply.

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

## Multi-machine sync

`chezmoi apply` only affects the machine it runs on. Each home is independent — macOS
(`/Users/cadeb/`) and Linux NFS (`/home/cadeb/`) don't share target files.

**Normal workflow — commit first, then sync remotes:**

```sh
# 1. Edit and apply locally
chezmoi edit ~/.ssh/config
chezmoi apply

# 2. Commit and push
cd ~/dotfiles
git add home/dot_ssh/config.tmpl
git commit -m "ssh: describe what changed"
git push

# 3. On each remote — pull and apply
ssh remote-host 'bash -l ~/dotfiles/bootstrap.sh update'
```

**If you applied locally without committing** (the wrong order), remotes are stale.
Quick workaround while you clean it up:

```sh
# Render the template locally and copy the result over
chezmoi cat ~/.ssh/config | ssh remote-host 'cat > ~/.ssh/config'
```

Then commit and push so the repo catches up.

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

Codex-specific note:
- `~/.codex/AGENTS.md` and `~/.codex/rules/` are intentionally Codex-specific; skills are shared from `~/.claude/skills` via the `~/.agents/skills` symlink
