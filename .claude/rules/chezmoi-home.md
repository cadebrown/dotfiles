---
paths:
  - "home/**"
---

# chezmoi templates and home/ sources

Templates in `home/*.tmpl` render on `chezmoi apply`. On shared NFS homes, **templates
must render identically on every machine** — otherwise machines overwrite each other.

- **Use `{{ .chezmoi.os }}`** (darwin/linux) for platform branching — this is stable across shared homes
- **Never use `{{ .chezmoi.arch }}`** or per-machine values in templates — use shell runtime detection instead
- Template variables: `{{ .name }}`, `{{ .email }}` (from chezmoi data), `{{ .chezmoi.os }}`, `{{ .chezmoi.homeDir }}`

## Shared partials

`home/.chezmoitemplates/` holds reusable template fragments:

- `agents-common.md` — engineering norms (how-I-work, no-shortcut-fixes, tool
  preferences, git) shared across all four tools' guidance files.
- `voice-common.md` — tone/communication + estimate conventions. Single source
  for "how output should read". Claude loads it via the `cade` output style
  (`home/dot_claude/output-styles/cade.md.tmpl`, system-prompt level); Codex,
  opencode, and pi include it directly in their always-on file. It is
  deliberately **not** in `agents-common.md`, so Claude doesn't load voice twice.
- `locale-env.sh` — the OS-branched locale block (macOS: LANG+LC_ALL; Linux:
  LOCPATH → `unset LC_ALL` → LANG). Included by BOTH login profiles AND both
  interactive rc files — embedded terminals (VS Code/Cursor Remote-SSH) spawn
  non-login shells that skip the profiles while inheriting a forwarded LC_ALL,
  so the guard must run in rc too. Uses `${_LOCAL_PLAT:-$HOME/.local}` since
  `_LOCAL_PLAT` is unset when the profile never ran.

Reference either from a `.tmpl` with:

```gotmpl
{{ template "agents-common.md" . }}
{{ template "voice-common.md" . }}
```

Edit a partial once and every consuming tool updates on the next `chezmoi apply`.
See [docs/usage/agents.md](../../docs/usage/agents.md).

## Shell profile invariants

- Shell profiles (`dot_zprofile.tmpl`, `dot_bash_profile.tmpl`) must stay in sync —
  same structure, same env, unless divergence is intentional and commented.
- Go env: `GOPATH=$LOCAL_PLAT/go` (module cache + workspace), `GOBIN=$ARCH_BIN`
  (binary install target — same dir as cargo/uv outputs, so no second PATH entry),
  `GOCACHE=$LOCAL_PLAT/go-build` (build cache, parallel to `CARGO_TARGET_DIR`).
- `$LOCAL_PLAT/venv/bin` was removed — Python CLI tools now use `uv tool install`
  (isolated venvs under `$LOCAL_PLAT/uv/tools/`).
- On Linux, `LOCPATH` must be exported before `LANG` (the export triggers the
  shell's internal `setlocale()`, which needs the brew-glibc locale data).

## Gotchas

- **ssh from macOS forwards `LC_ALL` and garbles remote copy/paste** — macOS ships
  `SendEnv LANG LC_*` in `/etc/ssh/ssh_config`, so the Mac's `LC_ALL=en_US.UTF-8` overrides
  the Linux profiles' LANG-only locale setup; on hosts without that system locale, system
  tmux re-encodes UTF-8 as latin-1 mojibake (`â€™`) that rides the clipboard. The guard
  (`unset LC_ALL` on Linux) lives in the `locale-env.sh` partial, included by the profiles
  AND both rc files — the rc inclusion is load-bearing: VS Code/Cursor Remote-SSH embedded
  terminals are non-login shells that skip the profiles but inherit the forwarded LC_ALL
  through the remote server process (symptom there: copied text pastes with `Â`/`â€™`).
  Run `tmux kill-server` once after applying. A user-level `SendEnv -LC_*` can't fix it
  (user config is parsed before the system default adds the patterns).
  See docs/usage/troubleshooting.md.
- **Test `~/.homebrew/bin/brew`, never `-e ~/.homebrew`** — Homebrew stores tap-trust
  state at `~/.homebrew/trust.json` on macOS, so a bare directory test misroutes the
  shell profiles onto the Linux user-prefix branch (bit us June 2026; both profile
  templates now guard on the binary).
- **`sourceDir` in chezmoi.toml must be a top-level key** — not inside `[data]`. Misplacing
  it silently breaks `chezmoi diff` and `chezmoi update`.
- **Binary files like `dot_iterm2/*.plist` are not templates** — no `.tmpl` extension.
- **`~/.claude` (the dir) must never be symlinked to scratch** — chezmoi manages
  `home/dot_claude/` as a real directory. If `scratch.sh` symlinks `~/.claude` itself,
  `chezmoi apply` replaces the symlink with a directory containing only managed files,
  orphaning all conversation history, sessions, and file-history on scratch. The supported
  offload is one level down: `scratch.sh` symlinks the heavy *unmanaged* subdirs
  (`projects`, `plugins`, `file-history`, via `DF_CLAUDE_LINKS`) into
  `$PATHS/.claude/`, which chezmoi leaves alone (`dot_claude` is not `exact_` and
  `.chezmoiremove` never lists them). Tradeoff: those become per-machine like `~/.local`
  — auto-memory under `projects/<proj>/memory/` stops syncing across the NFS fleet (`~/kb`
  stays the cross-machine layer). Drop `projects` from `DF_CLAUDE_LINKS` to keep history on NFS.
- **nvm lazy loading design:** `home/dot_zprofile.tmpl` (PATH entry) +
  `home/dot_zshrc.tmpl` (oh-my-zsh plugin).
