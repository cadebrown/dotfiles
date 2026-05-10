#!/usr/bin/env bash
# install/plat-decommission.sh — remove ~/.local/plat_*/ directories
#
# Use this when migrating from per-PLAT directory isolation to the flat
# ~/.local/ layout (DF_USE_PLAT=0, the default). Run AFTER setting
# use_plat=false (or unsetting DF_USE_PLAT) and applying chezmoi.
#
# Safety:
#   - Standalone only — NEVER invoked by bootstrap.sh, including upgrade mode.
#   - Refuses to run if DF_USE_PLAT=1 is currently set in the environment
#     (would nuke the active install dir).
#   - Asks for explicit confirmation before deleting (skip with DF_FORCE=1).
#   - Idempotent — running with no plat_* dirs is a no-op.
#
# Usage:
#   bash ~/dotfiles/install/plat-decommission.sh         # interactive
#   DF_FORCE=1 bash ~/dotfiles/install/plat-decommission.sh   # non-interactive
#
# After running, re-bootstrap to repopulate the flat layout:
#   ~/dotfiles/bootstrap.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "PLAT decommission"

if [[ "${DF_USE_PLAT:-0}" == "1" ]]; then
    die "DF_USE_PLAT=1 is set — PLAT isolation is the active install layout.
       Set DF_USE_PLAT=0 (or remove use_plat=true from chezmoi data) before
       decommissioning, or this would nuke the dirs you're currently using."
fi

# Resolve through scratch symlink if present so we look in the real location.
_local_root="$HOME/.local"
if [[ -L "$_local_root" ]]; then
    _local_root="$(readlink -f "$_local_root")"
fi

_plat_dirs=()
for _d in "$_local_root"/plat_*/; do
    [[ -d "$_d" ]] && _plat_dirs+=("${_d%/}")
done

if [[ ${#_plat_dirs[@]} -eq 0 ]]; then
    log_okay "No PLAT directories at $_local_root/plat_* — nothing to do"
    exit 0
fi

log_info "Found PLAT directories to remove (under $_local_root):"
for _d in "${_plat_dirs[@]}"; do
    _size="$(du -sh "$_d" 2>/dev/null | cut -f1)"
    printf "    %s  (%s)\n" "$_d" "${_size:-?}"
done
printf "\n"

if [[ "${DF_FORCE:-0}" != "1" ]]; then
    printf "Delete all of the above? [y/N] "
    # `|| true` so set -e doesn't kill us if read returns non-zero (no TTY,
    # closed stdin). Treat any non-y answer as abort.
    read -r _yn || _yn=""
    case "$_yn" in
        y|Y|yes|YES) ;;
        *) die "Aborted by user (use DF_FORCE=1 to skip this prompt)" ;;
    esac
fi

for _d in "${_plat_dirs[@]}"; do
    log_info "Removing $_d ..."
    rm -rf "$_d"
    log_okay "Removed $_d"
done

log_okay "PLAT decommission complete"
log_info ""
log_info "Next steps:"
log_info "  1. Open a new shell (or source ~/.zprofile) so _LOCAL_PLAT picks up the flat layout"
log_info "  2. Re-run bootstrap to repopulate ~/.local with fresh installs:"
log_info "       ~/dotfiles/bootstrap.sh"
