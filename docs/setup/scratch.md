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
   │                                         ├── .claude/
   ├── .claude/      ◀── real dir            │   ├── projects/   ◀── history + memory
   │   ├── projects     ──symlink──▶         │   ├── plugins/
   │   ├── plugins      ──symlink──▶         │   └── file-history/
   │   ├── file-history ─symlink──▶          │
   │   ├── settings.json   ◀── chezmoi-managed, stays local
   │   └── skills/         ◀── chezmoi-managed, stays local
   │                                         └── .codex/
   ├── .codex/       ◀── real dir                ├── sessions/   ◀── transcripts, the bulk
   │   ├── sessions        ─symlink──▶           ├── generated_images/
   │   ├── generated_images symlink──▶          ├── cache/ plugins/ attachments/
   │   ├── cache           ─symlink──▶           ├── shell_snapshots/ log/ backups/
   │   ├── plugins         ─symlink──▶           ├── .tmp/ tmp/
   │   ├── *.sqlite        ─symlink──▶           └── logs_2.sqlite (+ -wal, -shm)
   │   ├── config.toml     ◀── chezmoi-managed, stays local
   │   └── AGENTS.md       ◀── chezmoi-managed, stays local
   ├── dotfiles/     ◀── real dir, version controlled
   └── .config/      ◀── real dir, small files
```

`~/.claude` and `~/.codex` themselves stay **real directories** — chezmoi manages files inside them (`settings.json`, `skills/`, `config.toml`, `AGENTS.md`, hooks, profiles, themes), and a symlink at either path gets clobbered on `chezmoi apply`. Only the heavy *unmanaged* entries are redirected, controlled by `DF_CLAUDE_LINKS` and `DF_CODEX_LINKS`.

### Codex specifics

Codex keeps its loose SQLite state (`logs_N.sqlite`, `state_N.sqlite`, …) directly in `~/.codex`, and on a busy machine `logs_N` alone reaches several hundred MB — the largest item after `sessions/`. Those files are symlinked individually. SQLite canonicalizes a database path before deriving the `-wal`/`-shm` sibling names, so linking just the `.sqlite` file puts the whole write-ahead log on scratch too.

Two consequences worth knowing:

- **`~/.codex` migrates only when nothing holds it open.** A cross-filesystem move is copy-then-unlink, so a process with one of these files open would keep writing to the unlinked inode and lose those writes. The check is per-file (`/proc/*/fd`), not "is Codex running" — Codex leaves an `app-server` daemon resident for days with every file closed, and refusing on that would mean never migrating. If the script reports the tree is in use, quit Codex (its `app-server` too) and rerun `bash install/scratch.sh`.
- **The version suffix bumps with Codex's schema.** A new `logs_3.sqlite` is born on NFS and migrates on the next run; the same is true after a Codex self-repair replaces a database.

`~/.codex/memories/` is deliberately *not* migrated. It holds small markdown (`MEMORY.md`, `memory_summary.md`) that is worth keeping on NFS so it follows you across the fleet; only its SQLite index moves to scratch, matching how the qmd and cass indexes are already treated as per-machine.

### Why not `CODEX_HOME`?

Codex does expose a `CODEX_HOME` env var, and pointing it at scratch looks tidier than a handful of symlinks. It was rejected for two reasons:

1. It relocates the **whole** tree, including the chezmoi-managed config. chezmoi has no per-entry destination override, so `~/.codex` would have to leave chezmoi's control entirely and be deployed by `install/codex.sh` instead — on macOS too, where none of this is needed.
2. Any Codex launched **without** the variable set — an IDE extension, a cron job, a non-interactive `ssh host codex …` — silently starts a second, unconfigured `~/.codex`. That is the same silent-divergence failure the symlinks exist to prevent.

Subdir symlinks need no env var and hold in every launch context.

### Why not symlink the whole dir and `.chezmoiignore` it?

This *does* work, and it is the pattern `~/.local` already uses (see the non-darwin block in `home/.chezmoiignore`): once a path is ignored, chezmoi drops it from `chezmoi managed` and leaves an existing symlink there untouched across applies. A `symlink_dot_codex` entry is not an alternative — declaring it alongside the `dot_codex/` source directory fails with `.codex: inconsistent state`.

It was still rejected, because ignoring the directory means `install/codex.sh` has to re-implement the chezmoi attributes that `home/dot_codex/` relies on:

- `create_private_config.toml` — `create_` seeds `~/.codex/config.toml` **once** and never rewrites it, which is precisely what lets `codex.sh` own the file afterward; `private_` pins it to 600
- `executable_rtk-rewrite.sh` — 755
- `AGENTS.md.tmpl` — rendered from the shared `agents-common.md` / `voice-common.md` partials

Hand-rolling create-once, mode bits, and template rendering is exactly the kind of thing that drifts from what chezmoi actually does, and `chezmoi apply` would stop repairing edits to the Codex config. The `.chezmoiignore` line also becomes a cliff: delete it and chezmoi silently eats the symlink again, which is the original bug.

The payoff for all that is **1.5 MB out of 3.0 GB** — the managed config plus `skills/`, `memories/`, and `models_cache.json`. Not worth it. If `~/.codex` ever grows something large *outside* a subdirectory, add it to `DF_CODEX_LINKS` (directories) or let the `*.sqlite` glob pick it up, rather than revisiting this.

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
| `DF_CLAUDE_LINKS` | `projects:plugins:file-history` | Colon-separated `~/.claude` subdir names to redirect to scratch (never `~/.claude` itself — chezmoi owns it). Drop `projects` to keep conversation history + memory on NFS. |
| `DF_CODEX_LINKS` | `sessions:generated_images:cache:plugins:attachments:shell_snapshots:log:backups:.tmp:tmp` | Colon-separated `~/.codex` subdir names to redirect to scratch (never `~/.codex` itself). Set empty to leave `~/.codex` alone entirely, including its SQLite files. |
| `DF_DO_SCRATCH` | `1` (install mode), `0` (update/upgrade) | Skip scratch setup entirely. |

Setting any of `DF_LINKS`, `DF_CLAUDE_LINKS`, or `DF_CODEX_LINKS` to the empty string means "migrate nothing here" — unsetting it restores the default.

## What NOT to symlink

These look tempting but are traps:

- **`~/.claude/` and `~/.codex/` themselves** — chezmoi manages files in both. If either *directory* is symlinked, `chezmoi apply` replaces the symlink with a real directory containing only managed files, **orphaning all your conversation history, sessions, and transcripts on scratch** — silently, with no error. Neither is ever in `DF_LINKS`. The heavy *unmanaged* entries **are** redirected one level down via `DF_CLAUDE_LINKS` / `DF_CODEX_LINKS`, which chezmoi leaves alone — that's the supported way to get these off the quota.
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
