#!/usr/bin/env bash
# install/agent-tools.sh - deploy architecture-independent agent helper commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

log_section "agent helper commands"

_source="$DF_ROOT/home/dot_local/bin/executable_df-agent-doctor"
_destination="$ARCH_BIN/df-agent-doctor"

[[ -f "$_source" ]] || die "Missing agent doctor source: $_source"
ensure_dir "$ARCH_BIN"

if [[ -x "$_destination" ]] && cmp -s "$_source" "$_destination"; then
    log_okay "Agent doctor is current: $_destination"
else
    install -m 755 "$_source" "$_destination"
    log_okay "Installed agent doctor → $_destination"
fi

[[ -x "$_destination" ]] || die "Agent doctor is not executable: $_destination"
cmp -s "$_source" "$_destination" || die "Agent doctor deployment does not match its source"
