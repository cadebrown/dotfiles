#!/usr/bin/env bash
# install/agent-tools.sh - deploy architecture-independent agent helper commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

log_section "agent helper commands"

ensure_dir "$ARCH_BIN"

for _command in df-agent-doctor plugin-eval; do
    _source="$DF_ROOT/home/dot_local/bin/executable_$_command"
    _destination="$ARCH_BIN/$_command"
    [[ -f "$_source" ]] || die "Missing $_command source: $_source"

    if [[ -x "$_destination" ]] && cmp -s "$_source" "$_destination"; then
        log_okay "$_command is current: $_destination"
    else
        install -m 755 "$_source" "$_destination"
        log_okay "Installed $_command → $_destination"
    fi

    [[ -x "$_destination" ]] || die "$_command is not executable: $_destination"
    cmp -s "$_source" "$_destination" || die "$_command deployment does not match its source"
done
