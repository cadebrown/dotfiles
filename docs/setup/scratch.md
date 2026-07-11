# Scratch space

Some shared filesystems give you a tiny home quota and a much larger "scratch" partition (HPC clusters, lab racks, certain NAS setups). The bootstrap can transparently redirect heavy directories to scratch via symlinks, so the multi-GB Homebrew prefix and tool caches never touch NFS.

**You don't need this if your `$HOME` quota is fine.** Skip the rest of this page.

## How it works

`install/scratch.sh` (run as bootstrap step 0) symlinks selected `$HOME` directories into `$DF_SCRATCH/.paths/`. Existing contents are moved over before the symlink replaces the original directory.

```text
   $HOME/                                    $DF_SCRATCH/.paths/
   ├── .local        ──symlink──▶            ├── .local/        ◀── PLAT dirs, brew, cargo
   ├── .cache        ──symlink──▶            ├── .cache/        ◀── ccache, sccache, uv cache
   ├── .npm          ──symlink──▶            ├── .npm/
   ├── .nv           ──symlink──▶            ├── .nv/           ◀── NVIDIA shader cache
   ├── .vscode       ──symlink──▶            ├── .vscode/
   ├── .vscode-server ─symlink──▶            ├── .vscode-server/
   ├── .cursor       ──symlink──▶            ├── .cursor/
   ├── .cursor-server ─symlink──▶            ├── .cursor-server/
   ├── .oh-my-zsh    ──symlink──▶            ├── .oh-my-zsh/
   │                                         └── .claude/
   ├── .claude/      ◀── real dir                ├── projects/   ◀── history + memory
   │   ├── projects     ──symlink──▶             ├── plugins/
   │   ├── plugins      ──symlink──▶             ├── file-history/
   │   ├── file-history ─symlink──▶             └── ccline/
   │   ├── ccline       ──symlink──▶
   │   ├── settings.json   ◀── chezmoi-managed, stays local
   │   └── skills/         ◀── chezmoi-managed, stays local
   ├── dotfiles/     ◀── real dir, version controlled
   └── .config/      ◀── real dir, small files
```

`~/.claude` itself stays a **real directory** — chezmoi manages files inside it (`settings.json`, `skills/`, hook scripts), and a symlinked `~/.claude` gets clobbered on `chezmoi apply`. Only the heavy *unmanaged* subdirs are redirected, controlled by `DF_CLAUDE_LINKS`.

## Configuring

Either set `DF_SCRATCH` before running bootstrap:

```sh
DF_SCRATCH=/scratch/$USER ~/dotfiles/bootstrap.sh
```

…or pre-create a `~/scratch` symlink and let bootstrap auto-detect it:

```sh
ln -s /local/disk/$USER ~/scratch
~/dotfiles/bootstrap.sh
```

| Env var | Default | What it does |
|---|---|---|
| `DF_SCRATCH` | (unset) | Path to scratch root. Setting this enables scratch mode. |
| `DF_SCRATCH_LINK` | `~/scratch` | Symlink in `$HOME` pointing at scratch. Bootstrap creates this if `DF_SCRATCH` is set. |
| `DF_LINKS` | `~/.local:~/.cache:~/.vscode:~/.vscode-server:~/.cursor:~/.cursor-server:~/.nv:~/.npm:~/.oh-my-zsh:~/.oh-my-zsh-custom` | Colon-separated list of top-level dirs to symlink to scratch. Override to customize. |
| `DF_CLAUDE_LINKS` | `projects:plugins:file-history:ccline` | Colon-separated `~/.claude` subdir names to redirect to scratch (never `~/.claude` itself — chezmoi owns it). Drop `projects` to keep conversation history + memory on NFS. |
| `DF_DO_SCRATCH` | `1` (install mode), `0` (update/upgrade) | Skip scratch setup entirely. |

## What NOT to symlink

These look tempting but are traps:

- **`~/.claude/` itself** — chezmoi manages files here. If the *directory* is symlinked, `chezmoi apply` replaces the symlink with a real directory containing only managed files, **orphaning all your conversation history, sessions, and file-history on scratch**. It is never in `DF_LINKS`. The heavy *unmanaged* subdirs (`projects`, `plugins`, `file-history`, `ccline`) **are** redirected one level down via `DF_CLAUDE_LINKS`, which chezmoi leaves alone — that's the supported way to get `~/.claude` off the quota.
- **`~/.config/`** — small, fast, and chezmoi-managed. Many tools assume `XDG_CONFIG_HOME` is local-disk-fast (e.g. shell startup reads it constantly).
- **`~/dotfiles/`** — the repo itself. Cloned to `$HOME` directly so editor "open file" dialogs and IDE indexing work normally.
- **`~/.ssh/`** — security boundary. Local disk only.

## Filesystem caveats

- **tmpfs scratch** is detected and warned about — contents are lost on reboot. Fine for ephemeral state, fatal for the Homebrew prefix.
- **Cross-filesystem moves** can be slow on first bootstrap (existing `~/.local` may be tens of GB). Subsequent runs are no-ops.
- **NFS open-file locks** sometimes leave `.nfs*` silly-rename files behind during the move; the script logs a warning but doesn't fail.

## Re-running

`scratch.sh` is idempotent. If a path is already a symlink to the right target, it's left alone. If it's a real directory with new content, the script moves the new content and re-symlinks. If it's a symlink pointing somewhere unexpected, the script logs a warning and skips (won't silently overwrite an admin-set link).

To opt out without unwinding the symlinks (just stop redirecting new dirs):

```sh
DF_DO_SCRATCH=0 ~/dotfiles/bootstrap.sh
```

To fully unwind (move data back to real `$HOME`), do it manually — the script doesn't ship a "decommission scratch" mode.
