#!/usr/bin/env bash
# install/migrate-plat.sh — rename old PLAT dir to new format
#
# Old format: ~/.local/x86_64-Linux  ~/.local/aarch64-Linux  ~/.local/arm64-Darwin
# New format: ~/.local/plat_Linux_x86-64-v3  ~/.local/plat_Linux_aarch64  etc.
#
# Called automatically by bootstrap.sh step 0.3 when an old dir is detected.
# Safe to re-run: exits cleanly if already migrated or nothing to do.
#
# Usage:
#   bash ~/dotfiles/install/migrate-plat.sh
#   bash ~/dotfiles/install/migrate-plat.sh --dry-run   # preview only

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Build the old-format PLAT name for this machine
_old_arch="$(uname -m)"
[[ "$_old_arch" == "arm64" ]] && _old_arch="aarch64"
_OLD_PLAT="${_old_arch}-$(uname -s)"
unset _old_arch

# Resolve ~/.local to the real path (may be a scratch symlink)
_LOCAL_ROOT_REAL="$(readlink -f "$HOME/.local")"
_OLD_DIR="$_LOCAL_ROOT_REAL/$_OLD_PLAT"
_NEW_DIR="$_LOCAL_ROOT_REAL/$PLAT"

log_info "Old PLAT: $_OLD_PLAT → $_OLD_DIR"
log_info "New PLAT: $PLAT → $_NEW_DIR"

if [[ "$_OLD_DIR" == "$_NEW_DIR" ]]; then
    log_ok "PLAT format already current: $PLAT"
    exit 0
fi

if [[ ! -d "$_OLD_DIR" ]]; then
    log_info "Old PLAT dir not found — nothing to migrate"
    exit 0
fi

if [[ -d "$_NEW_DIR" ]]; then
    log_warn "New PLAT dir already exists: $_NEW_DIR"
    log_warn "Old dir still at: $_OLD_DIR"
    log_warn "Manual merge may be needed — skipping automatic migration"
    exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] Would rename: $_OLD_DIR → $_NEW_DIR"
    exit 0
fi

log_info "Renaming: $_OLD_DIR → $_NEW_DIR"
mv "$_OLD_DIR" "$_NEW_DIR"
log_ok "Migration complete: $PLAT"

# If ~/.local/$_OLD_PLAT was a directory inside scratch, the symlinks from
# ~/.local/$PLAT/* still resolve correctly (we moved the target, not the symlink).
# Print a reminder about updating chezmoi sourceDir if it stored the old PLAT path.
_CFG="$HOME/.config/chezmoi/chezmoi.toml"
if [[ -f "$_CFG" ]] && grep -q "$_OLD_PLAT" "$_CFG" 2>/dev/null; then
    log_warn "chezmoi.toml may reference old PLAT path:"
    grep "$_OLD_PLAT" "$_CFG" || true
    log_info "Run: chezmoi init --apply --force --source \"\$(chezmoi source-path)\""
fi
