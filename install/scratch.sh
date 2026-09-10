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
#     ├── .cass/                 ← symlinked from ~/.cass (session archive; ~10 GB
#     │                            of raw-mirror evidence, install/memory.sh)
#     ├── .nv/                   ← symlinked from ~/.nv (NVIDIA shader/optix cache)
#     ├── .npm/                  ← symlinked from ~/.npm (npm cache)
#     ├── .oh-my-zsh/            ← symlinked from ~/.oh-my-zsh
#     ├── .oh-my-zsh-custom/     ← symlinked from ~/.oh-my-zsh-custom
#     ├── kb/                    ← symlinked from ~/kb (knowledge base, install/memory.sh)
#     ├── .claude/               ← heavy *unmanaged* subdirs of ~/.claude (see note)
#     │   ├── projects/          ← symlinked from ~/.claude/projects (history + memory)
#     │   ├── plugins/           ← symlinked from ~/.claude/plugins
#     │   └── file-history/      ← symlinked from ~/.claude/file-history
#
# Which top-level dirs are migrated is controlled by DF_LINKS (colon-separated);
# ~/.claude subdirs by DF_CLAUDE_LINKS. Defaults are below.
#
# Note on ~/kb: on scratch, each machine has its OWN kb working copy — the
# git remote (not NFS) is the sync mechanism, which is the designed model
# (memory.sh prompts for a remote). Git on NFS is slow and lock-prone, and
# kb sits next to the qmd index reads, so local disk is the right home.
# Note: ~/.config is NOT migrated — chezmoi manages files inside it as a real directory.
# Note: ~/.claude is NEVER symlinked — chezmoi manages files inside it
#   (settings.json, skills/, config.toml, hooks) as a REAL directory, so a
#   symlinked ~/.claude gets clobbered on `chezmoi apply`
#   (replaced with a real dir holding only the managed files, orphaning history on
#   scratch). Instead we migrate the heavy *unmanaged* entries one level down, which
#   chezmoi never touches. Tradeoff: like ~/.local and ~/.cache, these become
#   per-machine — conversation history and auto-memory under projects/<proj>/memory/
#   stop syncing across the NFS fleet (~/kb, git-synced, stays the cross-machine layer).
#   Drop `projects` from DF_CLAUDE_LINKS to keep history on NFS and offload only caches.
# Codex is deliberately absent: its entire runtime is host-local and managed by
# install/codex.sh. Scratch must not relocate, symlink, or migrate Codex state.
#
# All variables are defined in _lib.sh:
#   SCRATCH          — absolute path to scratch root (empty if not configured)
#   PATHS            — $SCRATCH/.paths — the directory holding all symlink targets
#   DF_SCRATCH       — env var to set scratch root
#   DF_SCRATCH_LINK  — symlink in $HOME pointing to scratch (default: ~/scratch)
#   DF_LINKS         — colon-separated top-level dirs to migrate (override above defaults)
#   DF_CONFIG_LINKS  — colon-separated ~/.config subdir names to migrate
#   DF_CLAUDE_LINKS  — colon-separated ~/.claude subdir names to migrate
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

# link_managed_subdirs HOME_DIR LINKS
#   Offload heavy unmanaged entries of a chezmoi-managed directory. Chezmoi owns
#   files inside these as real dirs, so
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

# ~/.cursor is deliberately absent: chezmoi manages it as a real directory
# (cli-config.json, hooks/, hooks.json), so `chezmoi apply` replaces any symlink
# here with a real dir and orphans whatever was migrated — 304 MB sat unused on
# scratch while Cursor wrote to the home copy (Aug 2026). Same rule as
# ~/.claude; ~/.cursor-server is unmanaged and stays.
#
# These cache-shaped entries are the ones that actually fill a small home
# volume. TinyTeX is absent because install/latex.sh now keeps its compiled tree
# below LOCAL_PLAT, which is already redirected by the ~/.local entry.
_DEFAULT_LINKS="$HOME/.local:$HOME/.cache:$HOME/.cass:$HOME/.vscode:$HOME/.vscode-server:$HOME/.cursor-server:$HOME/.nv:$HOME/.npm:$HOME/.oh-my-zsh:$HOME/.oh-my-zsh-custom:$HOME/kb:$HOME/.computelab:$HOME/.agent-browser:$HOME/.gradle"
DF_LINKS="${DF_LINKS-$_DEFAULT_LINKS}"
unset _DEFAULT_LINKS

IFS=: read -ra _link_paths <<< "$DF_LINKS"
for _home_path in "${_link_paths[@]}"; do
    [[ -z "$_home_path" ]] && continue
    _name="$(basename "$_home_path")"
    link_to_scratch "$_home_path" "$_name"
done
unset _link_paths _home_path _name

# ~/.config and ~/.claude — migrate heavy unmanaged entries, never the dirs.
# Set-but-empty means "migrate nothing here" — hence ${VAR-default}, not ${VAR:-default}.

# ~/.config/Code is VS Code's user data — workspaceStorage and CachedData, 285 MB
# of it here, all of which VS Code rebuilds on demand. The directory above it is
# chezmoi-managed, so only the subdir moves.
_DEFAULT_CONFIG_LINKS="Code"
DF_CONFIG_LINKS="${DF_CONFIG_LINKS-$_DEFAULT_CONFIG_LINKS}"
unset _DEFAULT_CONFIG_LINKS
[[ -n "$DF_CONFIG_LINKS" ]] && link_managed_subdirs "$HOME/.config" "$DF_CONFIG_LINKS"

# ~/.cursor holds per-project agent history (projects/, worktrees/) that grows
# without bound, under a directory chezmoi owns. Migrating the whole thing is what
# went wrong before — `chezmoi apply` restored a real ~/.cursor and stranded the
# scratch copy, so Cursor silently started over with an empty history while 300 MB
# of it sat unreachable. Moving the subdirs merges that history back and keeps the
# managed files where chezmoi expects them.
_DEFAULT_CURSOR_LINKS="projects:worktrees"
DF_CURSOR_LINKS="${DF_CURSOR_LINKS-$_DEFAULT_CURSOR_LINKS}"
unset _DEFAULT_CURSOR_LINKS
[[ -n "$DF_CURSOR_LINKS" ]] && link_managed_subdirs "$HOME/.cursor" "$DF_CURSOR_LINKS"

_DEFAULT_CLAUDE_LINKS="projects:plugins:file-history"
DF_CLAUDE_LINKS="${DF_CLAUDE_LINKS-$_DEFAULT_CLAUDE_LINKS}"
unset _DEFAULT_CLAUDE_LINKS
link_managed_subdirs "$HOME/.claude" "$DF_CLAUDE_LINKS"

log_okay "Scratch space setup complete"
