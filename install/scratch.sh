#!/usr/bin/env bash
# install/scratch.sh - redirect large directories to scratch space
#
# On NFS homes with small quotas, ~/.local (~2-5 GB), ~/.cache,
# and oh-my-zsh can exhaust the quota during bootstrap. When scratch
# space is available (DF_SCRATCH env var or ~/scratch symlink),
# this script moves those directories to scratch and creates symlinks.
#
# Layout on scratch:
#   $SCRATCH/.paths/
#     ├── .local/                ← symlinked from ~/.local
#     ├── .cache/                ← symlinked from ~/.cache
#     ├── .nv/                   ← symlinked from ~/.nv (NVIDIA shader/optix cache)
#     ├── .npm/                  ← symlinked from ~/.npm (npm cache)
#     ├── .oh-my-zsh/            ← symlinked from ~/.oh-my-zsh
#     ├── .oh-my-zsh-custom/     ← symlinked from ~/.oh-my-zsh-custom
#     ├── kb/                    ← symlinked from ~/kb (knowledge base, install/memory.sh)
#     ├── .claude/               ← heavy *unmanaged* subdirs of ~/.claude (see note)
#     │   ├── projects/          ← symlinked from ~/.claude/projects (history + memory)
#     │   ├── plugins/           ← symlinked from ~/.claude/plugins
#     │   └── file-history/      ← symlinked from ~/.claude/file-history
#     └── .codex/                ← heavy *unmanaged* subdirs + SQLite state of ~/.codex
#         ├── sessions/          ← symlinked from ~/.codex/sessions (transcripts, the bulk)
#         ├── generated_images/  ← symlinked from ~/.codex/generated_images (per-session PNGs)
#         ├── cache/ plugins/ attachments/ shell_snapshots/ log/ backups/ .tmp/ tmp/
#         └── *.sqlite           ← symlinked from ~/.codex/*.sqlite (logs/state/goals)
#
# Which top-level dirs are migrated is controlled by DF_LINKS (colon-separated);
# ~/.claude and ~/.codex subdirs by DF_CLAUDE_LINKS / DF_CODEX_LINKS.
# Defaults: see _DEFAULT_LINKS / _DEFAULT_CLAUDE_LINKS / _DEFAULT_CODEX_LINKS below.
#
# Note on ~/kb: on scratch, each machine has its OWN kb working copy — the
# git remote (not NFS) is the sync mechanism, which is the designed model
# (memory.sh prompts for a remote). Git on NFS is slow and lock-prone, and
# kb sits next to the qmd index reads, so local disk is the right home.
# Note: ~/.config is NOT migrated — chezmoi manages files inside it as a real directory.
# Note: ~/.claude and ~/.codex are NEVER symlinked — chezmoi manages files inside them
#   (settings.json, skills/, config.toml, AGENTS.md, hooks, profiles, themes) as REAL
#   directories, so a symlinked ~/.claude or ~/.codex gets clobbered on `chezmoi apply`
#   (replaced with a real dir holding only the managed files, orphaning history on
#   scratch). Instead we migrate the heavy *unmanaged* entries one level down, which
#   chezmoi never touches. Tradeoff: like ~/.local and ~/.cache, these become
#   per-machine — conversation history and auto-memory under projects/<proj>/memory/
#   stop syncing across the NFS fleet (~/kb, git-synced, stays the cross-machine layer).
#   Drop `projects` from DF_CLAUDE_LINKS to keep history on NFS and offload only caches.
# Note on CODEX_HOME: Codex does expose one, but it relocates the WHOLE tree, including
#   the chezmoi-managed config — and any Codex launched without the var set (IDE
#   extension, cron, non-interactive ssh) silently starts a second, unconfigured
#   ~/.codex. Subdir symlinks need no env var and hold in every launch context.
# Note on ~/.codex/memories: markdown memory (MEMORY.md, memory_summary.md) stays on
#   NFS so it follows you across the fleet; only its SQLite index moves to scratch,
#   matching how qmd/cass indexes are already treated as per-machine.
#
# All variables are defined in _lib.sh:
#   SCRATCH          — absolute path to scratch root (empty if not configured)
#   PATHS            — $SCRATCH/.paths — the directory holding all symlink targets
#   DF_SCRATCH       — env var to set scratch root
#   DF_SCRATCH_LINK  — symlink in $HOME pointing to scratch (default: ~/scratch)
#   DF_LINKS         — colon-separated top-level dirs to migrate (override above defaults)
#   DF_CLAUDE_LINKS  — colon-separated ~/.claude subdir names to migrate
#   DF_CODEX_LINKS   — colon-separated ~/.codex subdir names to migrate (empty = skip;
#                      its loose *.sqlite files ride along, and the whole ~/.codex
#                      migration is skipped while any process holds a file there open)
#
# Safe to re-run: skips directories that are already correctly symlinked.
# No-op when no scratch space is detected.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

if [[ -z "$SCRATCH" ]]; then
    log_info "No scratch space detected (no \$DF_SCRATCH_LINK or \$DF_SCRATCH) — skipping"
    exit 0
fi

if [[ ! -d "$SCRATCH" ]]; then
    die "SCRATCH=$SCRATCH does not exist or is not a directory"
fi

if [[ ! -w "$SCRATCH" ]]; then
    die "SCRATCH=$SCRATCH is not writable"
fi

# Warn if scratch is tmpfs (data lost on reboot)
if command -v findmnt &>/dev/null; then
    _fstype="$(findmnt -n -o FSTYPE --target "$SCRATCH" 2>/dev/null || true)"
    if [[ "$_fstype" == "tmpfs" ]]; then
        log_warn "Scratch space is tmpfs — contents will be lost on reboot"
    fi
fi

# Migrate from old .homelinks layout (renamed to .paths in 2026-03)
_OLD_PATHS="$SCRATCH/.homelinks"
if [[ -d "$_OLD_PATHS" && ! -d "$PATHS" ]]; then
    log_info "Migrating $SCRATCH/.homelinks → $SCRATCH/.paths"
    mv "$_OLD_PATHS" "$PATHS"
    log_okay "Migration done — updating any symlinks that still point to .homelinks"
    # Fix any symlinks in $HOME that still target the old path
    for _link in "$HOME/.local" "$HOME/.cache" "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh-custom"; do
        if [[ -L "$_link" ]]; then
            _target="$(readlink "$_link")"
            _new_target="${_target/.homelinks/.paths}"
            if [[ "$_target" != "$_new_target" && -e "$_new_target" ]]; then
                ln -sfn "$_new_target" "$_link"
                log_okay "Updated: $_link → $_new_target"
            fi
        fi
    done
fi

# _verify_copy SRC DST
#   Returns 0 iff every real entry under SRC also exists under DST. Ignores
#   ephemeral NFS silly-rename files (.nfs*), which cp legitimately cannot copy.
#   Used to decide whether a copy was complete enough that deleting the source
#   is safe — a partial copy must never lead to source removal.
_verify_copy() {
    local src="$1" dst="$2" rel missing=0
    while IFS= read -r -d '' rel; do
        [[ -e "$dst/$rel" || -L "$dst/$rel" ]] && continue
        log_warn "  missing after copy: $rel"
        missing=1
    done < <(cd "$src" && find . -mindepth 1 ! -name '.nfs*' -print0 2>/dev/null)
    return "$missing"
}

# link_to_scratch HOME_PATH PATHS_NAME
#   HOME_PATH:   the path in $HOME to symlink (e.g. ~/.local)
#   PATHS_NAME:  name under $PATHS (e.g. .local)
#
#   If HOME_PATH is already a symlink to the right place → skip
#   If HOME_PATH is a real directory → move contents to scratch, replace with symlink
#   If HOME_PATH doesn't exist → create scratch target, create symlink
link_to_scratch() {
    local home_path="$1"
    local scratch_target="$PATHS/$2"

    # Already correct symlink
    if [[ -L "$home_path" ]]; then
        local current_target
        current_target="$(readlink -f "$home_path")"
        if [[ "$current_target" == "$(readlink -f "$scratch_target")" ]]; then
            log_okay "Already linked: $home_path → $scratch_target"
            return 0
        else
            log_warn "$home_path is a symlink to $current_target, not $scratch_target — skipping"
            return 0
        fi
    fi

    ensure_dir "$scratch_target"

    # Real directory with contents — copy to scratch, VERIFY, then replace.
    # The original is removed only after the copy is confirmed complete; a failed
    # or partial copy leaves the source untouched rather than risking data loss.
    if [[ -d "$home_path" ]]; then
        log_info "Moving $home_path → $scratch_target"
        if ! cp -a "$home_path/." "$scratch_target/"; then
            # cp returns non-zero on benign junk too (NFS .nfs* files, sockets,
            # dangling symlinks). Only refuse if a real entry is actually missing.
            if ! _verify_copy "$home_path" "$scratch_target"; then
                log_fail "Copy of $home_path → $scratch_target incomplete — leaving original in place"
                return 1
            fi
            log_warn "cp reported errors for $home_path but all real entries verified — continuing"
        fi
        # Copy confirmed. Rename the original aside (handles NFS open-file locks
        # better than rm -rf, which trips on .nfs* silly-rename files), swap in the
        # symlink, then remove the old copy.
        _old="${home_path}.old.$$"
        mv "$home_path" "$_old"
        ln -sfn "$scratch_target" "$home_path"
        log_okay "Linked: $home_path → $scratch_target"
        rm -rf "$_old" 2>/dev/null || log_warn "Could not fully remove $_old (NFS busy files?) — clean up later"
        return 0
    fi

    # Path doesn't exist yet — create symlink
    ensure_dir "$(dirname "$home_path")"
    ln -sfn "$scratch_target" "$home_path"
    log_okay "Linked: $home_path → $scratch_target"
}

# link_file_to_scratch HOME_FILE PATHS_NAME
#   Single-file variant of link_to_scratch, for SQLite databases sitting loose in a
#   chezmoi-managed directory. SQLite canonicalizes the database path before deriving
#   the "-wal"/"-shm" sibling names, so linking just the .sqlite file puts the whole
#   write-ahead log on scratch too — but any EXISTING siblings must travel with it,
#   or the next open finds a database newer than its log.
link_file_to_scratch() {
    local home_file="$1"
    local scratch_target="$PATHS/$2"
    local target_dir sib sibs=()

    if [[ -L "$home_file" ]]; then
        if [[ "$(readlink -f "$home_file")" == "$(readlink -f "$scratch_target")" ]]; then
            log_okay "Already linked: $home_file → $scratch_target"
        else
            log_warn "$home_file is a symlink to $(readlink -f "$home_file"), not $scratch_target — skipping"
        fi
        return 0
    fi

    # Gone from $HOME but present on scratch — a crash or a Codex self-repair dropped
    # the symlink. Restore it rather than leaving the migrated database stranded.
    if [[ ! -e "$home_file" ]]; then
        [[ -f "$scratch_target" ]] || return 0
        ln -sfn "$scratch_target" "$home_file"
        log_okay "Relinked: $home_file → $scratch_target"
        return 0
    fi

    [[ -f "$home_file" ]] || return 0

    for sib in "$home_file" "$home_file-wal" "$home_file-shm"; do
        [[ -f "$sib" ]] && sibs+=("$sib")
    done

    target_dir="$(dirname "$scratch_target")"
    ensure_dir "$target_dir"
    for sib in "${sibs[@]}"; do
        if ! cp -p "$sib" "$target_dir/$(basename "$sib")"; then
            log_fail "Copy of $sib → $target_dir failed — leaving $home_file in place"
            return 1
        fi
    done
    rm -f "${sibs[@]}"
    ln -sfn "$scratch_target" "$home_file"
    log_okay "Linked: $home_file → $scratch_target"
}

# _codex_in_use
#   True while any process holds a file under ~/.codex open. A cross-filesystem move is
#   copy-then-unlink, so such a process would go on writing to the unlinked inode and
#   lose those commits — fatal for the SQLite databases, lossy for a live transcript.
#
#   Deliberately NOT "is codex running": Codex leaves an app-server daemon resident for
#   days with every file closed, so a process check would refuse forever on a machine
#   that is in fact safe to migrate. Falls back to that coarser test only where /proc
#   is unavailable, which scratch space (Linux-only in practice) never hits.
_codex_in_use() {
    if [[ -d /proc/self/fd ]]; then
        [[ -n "$(find /proc/[0-9]*/fd -lname "$HOME/.codex/*" -print -quit 2>/dev/null)" ]]
    else
        command -v pgrep &>/dev/null && pgrep -x codex &>/dev/null
    fi
}

# link_managed_subdirs HOME_DIR LINKS
#   Offload the heavy *unmanaged* entries of a chezmoi-managed directory (~/.claude,
#   ~/.codex). See the header note: chezmoi owns files inside these as real dirs, so
#   the dir itself must stay real. One level down is safe — neither source is an
#   exact_ dir and .chezmoiremove never lists these subdirs, so chezmoi leaves the
#   symlinks alone. Targets nest under $PATHS/<dirname>/<sub>.
link_managed_subdirs() {
    local home_dir="$1" links="$2" name sub subs=()
    name="$(basename "$home_dir")"

    if [[ -L "$home_dir" ]]; then
        log_warn "$home_dir is a symlink — chezmoi expects a real dir here; skipping $name subdir migration"
        return 0
    fi

    IFS=: read -ra subs <<< "$links"
    for sub in "${subs[@]}"; do
        [[ -z "$sub" ]] && continue
        link_to_scratch "$home_dir/$sub" "$name/$sub"
    done
}

log_info "Scratch: $SCRATCH"
log_info "Paths:   $PATHS"

_DEFAULT_LINKS="$HOME/.local:$HOME/.cache:$HOME/.vscode:$HOME/.vscode-server:$HOME/.cursor:$HOME/.cursor-server:$HOME/.nv:$HOME/.npm:$HOME/.oh-my-zsh:$HOME/.oh-my-zsh-custom:$HOME/kb"
DF_LINKS="${DF_LINKS-$_DEFAULT_LINKS}"
unset _DEFAULT_LINKS

IFS=: read -ra _link_paths <<< "$DF_LINKS"
for _home_path in "${_link_paths[@]}"; do
    [[ -z "$_home_path" ]] && continue
    _name="$(basename "$_home_path")"
    link_to_scratch "$_home_path" "$_name"
done
unset _link_paths _home_path _name

# ~/.claude and ~/.codex — migrate the heavy *unmanaged* entries, never the dirs
# themselves. See the header note and link_managed_subdirs.
# Set-but-empty means "migrate nothing here" — hence ${VAR-default}, not ${VAR:-default}.
_DEFAULT_CLAUDE_LINKS="projects:plugins:file-history"
DF_CLAUDE_LINKS="${DF_CLAUDE_LINKS-$_DEFAULT_CLAUDE_LINKS}"
unset _DEFAULT_CLAUDE_LINKS
link_managed_subdirs "$HOME/.claude" "$DF_CLAUDE_LINKS"

_DEFAULT_CODEX_LINKS="sessions:generated_images:cache:plugins:attachments:shell_snapshots:log:backups:.tmp:tmp"
DF_CODEX_LINKS="${DF_CODEX_LINKS-$_DEFAULT_CODEX_LINKS}"
unset _DEFAULT_CODEX_LINKS

if [[ -n "$DF_CODEX_LINKS" ]] && _codex_in_use; then
    log_warn "A process is holding ~/.codex open — skipping its migration"
    log_warn "  quit Codex (its app-server too), then rerun: bash install/scratch.sh"
elif [[ -n "$DF_CODEX_LINKS" ]]; then
    link_managed_subdirs "$HOME/.codex" "$DF_CODEX_LINKS"

    # Loose SQLite state (logs_N/state_N/goals_N/memories_N.sqlite) is the hottest-
    # written part of the tree and the largest after sessions/. The version suffix
    # bumps with Codex's schema, so match by glob: a new generation is born on NFS
    # and migrates on the next run.
    #
    # Both sides of the glob: $HOME finds databases still to migrate, scratch finds
    # ones whose symlink went missing (a crash, or a Codex self-repair). _seen keeps
    # a database present in both from being logged twice.
    if [[ ! -L "$HOME/.codex" ]]; then
        _seen=""
        for _db in "$HOME"/.codex/*.sqlite "$PATHS"/.codex/*.sqlite; do
            [[ -e "$_db" ]] || continue
            _name="$(basename "$_db")"
            [[ "$_seen" == *":$_name:"* ]] && continue
            _seen="$_seen:$_name:"
            link_file_to_scratch "$HOME/.codex/$_name" ".codex/$_name"
        done
        unset _db _name _seen
    fi
fi

log_okay "Scratch space setup complete"
