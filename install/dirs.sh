#!/usr/bin/env bash
# install/dirs.sh - create home directory structure
#
# Creates standard directories in $HOME. When scratch space is available,
# these become symlinks directly under $SCRATCH (not under .paths/).
#
# Env vars:
#   DF_DIRS  — colon-separated list of directories to create (default: dev:bones:misc)
#
# Safe to re-run: skips directories that already exist or are correctly linked.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Home directories"

DF_DIRS="${DF_DIRS:-dev:bones:misc}"

IFS=: read -ra _dirs <<< "$DF_DIRS"

for _name in "${_dirs[@]}"; do
    [[ -z "$_name" ]] && continue
    _home_path="$HOME/$_name"

    if [[ -n "$SCRATCH" ]]; then
        _scratch_target="$SCRATCH/$_name"

        # Already a correct symlink
        if [[ -L "$_home_path" ]]; then
            _cur="$(readlink -f "$_home_path" 2>/dev/null || true)"
            _want="$(readlink -f "$_scratch_target" 2>/dev/null || echo "$_scratch_target")"
            if [[ "$_cur" == "$_want" ]]; then
                log_okay "$_home_path → $_scratch_target"
                continue
            fi
        fi

        ensure_dir "$_scratch_target"

        # Real directory with contents — move to scratch
        if [[ -d "$_home_path" && ! -L "$_home_path" ]]; then
            log_info "Moving $_home_path → $_scratch_target"
            cp -a "$_home_path/." "$_scratch_target/" 2>/dev/null || true
            _old="${_home_path}.old.$$"
            mv "$_home_path" "$_old"
            ln -sfn "$_scratch_target" "$_home_path"
            rm -rf "$_old" 2>/dev/null || true
            log_okay "$_home_path → $_scratch_target (migrated)"
            continue
        fi

        # Doesn't exist yet — create symlink
        if [[ ! -e "$_home_path" ]]; then
            ln -sfn "$_scratch_target" "$_home_path"
            log_okay "$_home_path → $_scratch_target"
            continue
        fi

        log_warn "$_home_path exists but is not a symlink — skipping"
    else
        # No scratch — just mkdir
        if [[ -d "$_home_path" ]]; then
            log_okay "$_home_path"
        else
            mkdir -p "$_home_path"
            log_okay "$_home_path (created)"
        fi
    fi
done

unset _dirs _name _home_path _scratch_target _cur _want _old
