#!/usr/bin/env bash
# install/git-tools.sh - install architecture-independent Git helpers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

source_path="$DF_ROOT/home/dot_local/bin/executable_git-wt"
destination="$ARCH_BIN/git-wt"

[[ -f "$source_path" ]] || die "Missing Git worktree helper: $source_path"
ensure_dir "$ARCH_BIN"

if [[ -x "$destination" ]] && cmp -s "$source_path" "$destination"; then
    log_okay "Git worktree helper is current: $destination"
else
    install -m 755 "$source_path" "$destination"
    log_okay "Installed Git worktree helper → $destination"
fi
