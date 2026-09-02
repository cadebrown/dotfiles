#!/usr/bin/env bash
# install/lean.sh - Lean 4 toolchain via elan (+ default toolchain for Mathlib work)
#
# elan is Lean's rustup: user-local, no sudo, works on macOS and no-sudo Linux.
# ELAN_HOME is PLAT-isolated (_lib.sh / shell profiles) — toolchains are
# arch-specific binaries, ~1.5 GB each.
#
# Projects pin their own toolchain via a `lean-toolchain` file; elan downloads
# and dispatches automatically on entering the directory. The default toolchain
# below only makes bare `lean`/`lake` work outside projects.
#
# Mathlib: prefer `lake exe cache get` (~5-7 GB under ~/.cache/mathlib);
# building from source is the supported fallback for cache misses, custom
# revisions, and forks — budget 16 GB+ RAM there.
#
# Proof gate for AI-generated/exported proofs (see math-common.md): no `sorry`
# → `lake build` → axiom check → `lean4checker --fresh` (lean4checker is built
# per-toolchain from leanprover/lean4checker — per-project, not installed here).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Lean 4 toolchain (elan)"

# Pin the default; bump deliberately alongside Mathlib releases.
DF_LEAN_TOOLCHAIN="${DF_LEAN_TOOLCHAIN:-leanprover/lean4:v4.33.1}"

ensure_dir "$ELAN_HOME"

if [[ -x "$ELAN_HOME/bin/elan" ]]; then
    log_okay "elan already installed: $("$ELAN_HOME/bin/elan" --version 2>/dev/null | head -1)"
else
    log_info "Installing elan → $ELAN_HOME"
    # --no-modify-path: shell profiles already export ELAN_HOME/bin on PATH.
    run_logged sh -c "curl -sSf https://elan.lean-lang.org/elan-init.sh | ELAN_HOME='$ELAN_HOME' sh -s -- -y --no-modify-path --default-toolchain none"
    [[ -x "$ELAN_HOME/bin/elan" ]] || die "elan install failed (no $ELAN_HOME/bin/elan)"
    log_okay "elan: $("$ELAN_HOME/bin/elan" --version 2>/dev/null | head -1)"
fi

_elan="$ELAN_HOME/bin/elan"

# Only elan itself. `elan update` is deliberately not run: every toolchain here
# is an exact pin (ours below, projects' via lean-toolchain), so it would either
# no-op or pull a surprise 1.5 GB for anyone tracking a channel.
if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Updating elan"
    run_logged "$_elan" self update || die "elan self update failed"
fi

if "$_elan" toolchain list 2>/dev/null | grep -q "${DF_LEAN_TOOLCHAIN##*:}"; then
    log_okay "toolchain present: $DF_LEAN_TOOLCHAIN"
else
    log_info "Installing default toolchain $DF_LEAN_TOOLCHAIN (~1.5 GB)"
    run_logged "$_elan" toolchain install "$DF_LEAN_TOOLCHAIN"
fi
run_logged "$_elan" default "$DF_LEAN_TOOLCHAIN"

# Healthcheck — lake ships inside the toolchain.
_lean_version="$("$ELAN_HOME/bin/lean" --version 2>&1)" \
    || die "lean does not start through the elan shim in $ELAN_HOME/bin: $_lean_version"
_lake_version="$("$ELAN_HOME/bin/lake" --version 2>&1)" \
    || die "lake does not start through the elan shim in $ELAN_HOME/bin: $_lake_version"
log_okay "lean: $(head -1 <<< "$_lean_version")"
log_okay "lake: $(head -1 <<< "$_lake_version")"

log_okay "Lean toolchain ready (new Mathlib project: lake +leanprover-community/mathlib4:lean-toolchain new <name> math && cd <name> && lake exe cache get)"
