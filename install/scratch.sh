#!/usr/bin/env bash
# install/scratch.sh - redirect large directories to scratch space
#
# On NFS homes with small quotas, ~/.local (~2-5 GB), ~/.cache,
# and oh-my-zsh can exhaust the quota during bootstrap. When scratch
# space is available (DOTFILES_SCRATCH_PATH env var or ~/scratch symlink),
# this script moves those directories to scratch and creates symlinks.
#
# Layout on scratch:
#   $SCRATCH/.paths/
#     ├── .local/                ← symlinked from ~/.local
#     └── .cache/                ← symlinked from ~/.cache
#
# Which dirs are migrated is controlled by DOTFILES_LINKS_PATHS (colon-separated).
# Default: ~/.local:~/.cache
# Note: ~/.config is NOT migrated — chezmoi manages files inside it as a real directory.
# Note: ~/.oh-my-zsh and ~/.oh-my-zsh-custom are NOT migrated — install/zsh.sh installs fresh.
#
# All variables are defined in _lib.sh:
#   SCRATCH               — absolute path to scratch root (empty if not configured)
#   PATHS                 — $SCRATCH/.paths — the directory holding all symlink targets
#   DOTFILES_SCRATCH_PATH — env var to set scratch root
#   DOTFILES_SCRATCH_LINK — symlink in $HOME pointing to scratch (default: ~/scratch)
#   DOTFILES_LINKS_PATHS  — colon-separated dirs to migrate (override above defaults)
#
# Safe to re-run: skips directories that are already correctly symlinked.
# No-op when no scratch space is detected.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

if [[ -z "$SCRATCH" ]]; then
    log_info "No scratch space detected (no \$DOTFILES_SCRATCH_LINK or \$DOTFILES_SCRATCH_PATH) — skipping"
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
    log_ok "Migration done — updating any symlinks that still point to .homelinks"
    # Fix any symlinks in $HOME that still target the old path
    for _link in "$HOME/.local" "$HOME/.cache" "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh-custom"; do
        if [[ -L "$_link" ]]; then
            _target="$(readlink "$_link")"
            _new_target="${_target/.homelinks/.paths}"
            if [[ "$_target" != "$_new_target" && -e "$_new_target" ]]; then
                ln -sfn "$_new_target" "$_link"
                log_ok "Updated: $_link → $_new_target"
            fi
        fi
    done
fi

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
            log_ok "Already linked: $home_path → $scratch_target"
            return 0
        else
            log_warn "$home_path is a symlink to $current_target, not $scratch_target — skipping"
            return 0
        fi
    fi

    ensure_dir "$scratch_target"

    # Real directory with contents — move to scratch
    if [[ -d "$home_path" ]]; then
        log_info "Moving $home_path → $scratch_target"
        cp -a "$home_path/." "$scratch_target/" 2>/dev/null || true
        # Rename old dir out of the way (handles NFS open-file locks better
        # than rm -rf, which fails on .nfs* silly-rename files).
        _old="${home_path}.old.$$"
        mv "$home_path" "$_old"
        ln -sfn "$scratch_target" "$home_path"
        log_ok "Linked: $home_path → $scratch_target"
        rm -rf "$_old" 2>/dev/null || log_warn "Could not fully remove $_old (NFS busy files?) — clean up later"
        return 0
    fi

    # Path doesn't exist yet — create symlink
    ensure_dir "$(dirname "$home_path")"
    ln -sfn "$scratch_target" "$home_path"
    log_ok "Linked: $home_path → $scratch_target"
}

log_info "Scratch: $SCRATCH"
log_info "Paths:   $PATHS"

_DEFAULT_LINKS="$HOME/.local:$HOME/.cache"
DOTFILES_LINKS_PATHS="${DOTFILES_LINKS_PATHS:-$_DEFAULT_LINKS}"
unset _DEFAULT_LINKS

IFS=: read -ra _link_paths <<< "$DOTFILES_LINKS_PATHS"
for _home_path in "${_link_paths[@]}"; do
    [[ -z "$_home_path" ]] && continue
    _name="$(basename "$_home_path")"
    link_to_scratch "$_home_path" "$_name"
done
unset _link_paths _home_path _name

log_ok "Scratch space setup complete"
