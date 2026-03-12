#!/usr/bin/env bash
# install/scratch.sh - redirect large directories to scratch space
#
# On NFS homes with small quotas, ~/.local (~2-5 GB), ~/.cache,
# and oh-my-zsh can exhaust the quota during bootstrap. When scratch
# space is available (~/scratch symlink or DOTFILES_SCRATCH env var),
# this script moves those directories to scratch and creates symlinks.
#
# Layout on scratch:
#   $SCRATCH/.homelinks/         ← configurable via SCRATCH_HOME_DIR
#     ├── .local/                ← symlinked from ~/.local
#     ├── .cache/                ← symlinked from ~/.cache
#     ├── .oh-my-zsh/            ← symlinked from ~/.oh-my-zsh
#     ├── .oh-my-zsh-custom/     ← symlinked from ~/.oh-my-zsh-custom
#     └── dotfiles/              ← symlinked from ~/dotfiles (if repo exists there)
#
# Safe to re-run: skips directories that are already correctly symlinked.
# No-op when no scratch space is detected.

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

if [[ -z "$SCRATCH" ]]; then
    log_info "No scratch space detected (no ~/scratch or \$DOTFILES_SCRATCH) — skipping"
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

# Configurable subdirectory for home symlink targets
SCRATCH_HOME="${SCRATCH}/${SCRATCH_HOME_DIR:-.homelinks}"

# link_to_scratch HOME_PATH SCRATCH_NAME
#   HOME_PATH:    the path in $HOME to symlink (e.g. ~/.local)
#   SCRATCH_NAME: name under $SCRATCH_HOME (e.g. .local)
#
#   If HOME_PATH is already a symlink to the right place → skip
#   If HOME_PATH is a real directory → move contents to scratch, replace with symlink
#   If HOME_PATH doesn't exist → create scratch target, create symlink
link_to_scratch() {
    local home_path="$1"
    local scratch_target="$SCRATCH_HOME/$2"

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
        # Copy contents to scratch target
        cp -a "$home_path/." "$scratch_target/" 2>/dev/null || true
        # Rename old dir out of the way (handles NFS open-file locks better
        # than rm -rf, which fails on .nfs* silly-rename files).
        _old="${home_path}.old.$$"
        mv "$home_path" "$_old"
        # Create symlink at the now-free path
        ln -sfn "$scratch_target" "$home_path"
        log_ok "Linked: $home_path → $scratch_target"
        # Best-effort cleanup of the old dir (may fail on NFS busy files)
        rm -rf "$_old" 2>/dev/null || log_warn "Could not fully remove $_old (NFS busy files?) — clean up later"
        return 0
    fi

    # Path doesn't exist yet — create symlink
    ensure_dir "$(dirname "$home_path")"
    ln -sfn "$scratch_target" "$home_path"
    log_ok "Linked: $home_path → $scratch_target"
}

log_info "Scratch space: $SCRATCH"
log_info "Home links:    $SCRATCH_HOME"

# Always redirect these directories
link_to_scratch "$HOME/.local"           ".local"
link_to_scratch "$HOME/.cache"           ".cache"
link_to_scratch "$HOME/.oh-my-zsh"       ".oh-my-zsh"
link_to_scratch "$HOME/.oh-my-zsh-custom" ".oh-my-zsh-custom"

# Optional: redirect ~/.config (for very tight quotas)
if [[ "${SCRATCH_CONFIG:-0}" == "1" ]]; then
    link_to_scratch "$HOME/.config"      ".config"
fi

# Symlink the dotfiles repo itself to scratch
if [[ -d "$DOTFILES_ROOT" && ! -L "$DOTFILES_ROOT" ]]; then
    _scratch_repo="$SCRATCH_HOME/dotfiles"
    if [[ ! -d "$_scratch_repo" ]]; then
        log_info "Moving dotfiles repo to scratch"
        cp -a "$DOTFILES_ROOT/." "$_scratch_repo/" 2>/dev/null || true
        _old="${DOTFILES_ROOT}.old.$$"
        mv "$DOTFILES_ROOT" "$_old"
        ln -sfn "$_scratch_repo" "$DOTFILES_ROOT"
        log_ok "Linked: $DOTFILES_ROOT → $_scratch_repo"
        rm -rf "$_old" 2>/dev/null || log_warn "Could not fully remove $_old (NFS busy files?) — clean up later"
    fi
elif [[ -L "$DOTFILES_ROOT" ]]; then
    log_ok "Dotfiles repo already symlinked: $DOTFILES_ROOT → $(readlink -f "$DOTFILES_ROOT")"
fi

log_ok "Scratch space setup complete"
