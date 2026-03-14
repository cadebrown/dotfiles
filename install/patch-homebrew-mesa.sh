#!/usr/bin/env bash
# install/patch-homebrew-mesa.sh - patch the mesa formula for Linux custom prefix
#
# Two patches:
#
# Patch 1: drivers = "all" → "auto" for gallium/vulkan-drivers
#   The formula uses drivers="all" on Intel x86, which includes mobile/ARM GPU drivers
#   (freedreno, etnaviv, lima, panfrost, asahi). These fail to compile with GCC 12 on
#   x86 hosts due to AVX2 vector type conversion errors. "auto" limits to host-relevant
#   drivers: iris, crocus, llvmpipe, zink, nouveau, radeonsi, etc.
#
# Patch 2: remove ARM GPU tools from -Dtools=
#   Even with gallium-drivers=auto, the formula explicitly passes
#   -Dtools=...,freedreno,etnaviv,lima,panfrost,asahi,imagination,...
#   which forces libfreedreno_layout.a and similar libraries to be compiled.
#   fd6_tiled_memcpy.cc in libfreedreno_layout fails with the same GCC 12 AVX2 error.
#   Fix: remove the ARM-specific tools (freedreno,etnaviv,lima,panfrost,asahi,imagination).
#
# Safe to re-run: patches are idempotent (checked before applying).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping mesa patch"; exit 0; }

MESA_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/m/mesa.rb"

[[ -f "$MESA_RB" ]] || { log_warn "mesa.rb not found at $MESA_RB — skipping"; exit 0; }

log_section "Patching mesa formula for Linux (x86 drivers only)"

# Helper: idempotent literal string replace using python
# Prints 'already', 'patched', or 'notfound'
_replace() {
    local path="$1" old="$2" new="$3"
    python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$path" "$old" "$new"
}

# Patch 1: drivers = "all" → "auto" for gallium/vulkan-drivers
# "auto" detects only drivers relevant to the host CPU/GPU architecture.
_result=$(_replace "$MESA_RB" \
    'drivers = Hardware::CPU.intel? ? "all" : "auto"' \
    'drivers = Hardware::CPU.intel? ? "auto" : "auto"')
case "$_result" in
    already)  log_okay "Patch 1 (drivers=auto) already applied" ;;
    patched)  log_okay "Patch 1: drivers=all → drivers=auto (excludes mobile/ARM GPU drivers)" ;;
    notfound) log_warn "Patch 1 target not found in mesa.rb — formula may have changed" ;;
esac

# Patch 2: remove ARM GPU tools from -Dtools=
# libfreedreno_layout.a is built by the 'freedreno' tool entry and fails on x86 with GCC 12.
# Remove: freedreno (Adreno), etnaviv (Vivante), lima (Mali Utgard),
#         panfrost (Mali Midgard/Bifrost), asahi (Apple Silicon), imagination (PowerVR)
# Keep:   drm-shim, glsl, intel, nir, nouveau, dlclose-skip
_result=$(_replace "$MESA_RB" \
    '-Dtools=drm-shim,etnaviv,freedreno,glsl,intel,nir,nouveau,lima,panfrost,asahi,imagination,dlclose-skip' \
    '-Dtools=drm-shim,glsl,intel,nir,nouveau,dlclose-skip')
case "$_result" in
    already)  log_okay "Patch 2 (tools=x86-only) already applied" ;;
    patched)  log_okay "Patch 2: removed ARM GPU tools from -Dtools= (freedreno,etnaviv,lima,panfrost,asahi,imagination)" ;;
    notfound) log_warn "Patch 2 target not found in mesa.rb — formula may have changed" ;;
esac

unset -f _replace

log_okay "mesa.rb patched successfully"
