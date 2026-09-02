#!/usr/bin/env bash
# install/julia.sh — manage the Julia release channel through juliaup.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Julia (juliaup)"

JULIA_CHANNEL="${DF_JULIA_CHANNEL:-release}"

if ! has juliaup; then
    die "juliaup is not on PATH — the selected Brewfile formula did not install successfully"
fi

ensure_dir "$JULIAUP_DEPOT_PATH"
ensure_dir "$JULIA_DEPOT_PATH"
export JULIAUP_DEPOT_PATH JULIA_DEPOT_PATH

_juliaup_status="$(juliaup status 2>/dev/null)" \
    || die "juliaup status failed with JULIAUP_DEPOT_PATH=$JULIAUP_DEPOT_PATH"
if awk -v channel="$JULIA_CHANNEL" \
    '$1 == channel || $2 == channel { found = 1 } END { exit !found }' \
    <<< "$_juliaup_status"; then
    log_okay "Julia channel present: $JULIA_CHANNEL"
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        log_info "Updating Julia channel: $JULIA_CHANNEL"
        run_logged juliaup update "$JULIA_CHANNEL"
    fi
else
    log_info "Installing Julia channel: $JULIA_CHANNEL"
    run_logged juliaup add "$JULIA_CHANNEL"
fi

run_logged juliaup default "$JULIA_CHANNEL"
if ! _julia_health="$(julia --startup-file=no --history-file=no -e 'VERSION' 2>&1)"; then
    die "Julia channel $JULIA_CHANNEL is installed but the runtime does not start: $_julia_health"
fi
log_okay "Julia: $(julia --version 2>&1 | head -1)"
