#!/usr/bin/env bash
# install/patch-homebrew-mesa.sh — patch mesa.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# Homebrew installs mesa from source on custom prefixes (non-/home/linuxbrew).
# The mesa 26.x formula enables ALL GPU drivers on Intel x86, including drivers
# for mobile/embedded SoCs that are physically impossible to run on x86 hardware.
# Those ARM GPU drivers fail to compile with GCC 12 on x86 for two related reasons:
#
#   1. gallium-drivers / vulkan-drivers = "all" on Intel x86
#      The formula sets:
#        drivers = Hardware::CPU.intel? ? "all" : "auto"
#      "all" compiles every driver unconditionally, including freedreno (Qualcomm
#      Adreno), etnaviv (Vivante), lima (ARM Mali Utgard), panfrost (Mali
#      Midgard/Bifrost), and asahi (Apple Silicon). These drivers contain
#      AVX2-vectorised memcpy routines (e.g. fd6_tiled_memcpy.cc) that use
#      ARM/Adreno-specific intrinsics expressed as GCC vector extensions.
#      GCC 12 on x86 rejects implicit conversion between __vector(8) float and
#      __m256i / __m256d with "cannot convert" errors.
#      Upstream reference: https://gitlab.freedesktop.org/mesa/mesa/-/issues/
#
#   2. -Dtools= explicitly lists ARM GPU debug tools
#      Even when gallium-drivers=auto (which skips the ARM gallium drivers),
#      the formula still passes:
#        -Dtools=drm-shim,etnaviv,freedreno,glsl,intel,nir,nouveau,lima,panfrost,asahi,imagination,dlclose-skip
#      The 'freedreno' entry in -Dtools forces meson to build libfreedreno_layout.a
#      unconditionally, which contains the same fd6_tiled_memcpy.cc that fails.
#      This is the non-obvious part: driver selection and tool selection are
#      independent in mesa's meson build system.
#
# ─── WHAT THE PATCHES DO ────────────────────────────────────────────────────────
#
# Patch 1 — gallium/vulkan-drivers=auto on Intel x86
#   Changes: drivers = Hardware::CPU.intel? ? "all" : "auto"
#        to: drivers = Hardware::CPU.intel? ? "auto" : "auto"
#   meson's "auto" autodetects only the drivers relevant to the host GPU hardware.
#   On a headless x86 server with an NVIDIA GPU this enables: iris, crocus, i915,
#   llvmpipe, softpipe, zink, nouveau, radeonsi, r300, r600, virgl, svga, swrast.
#   Nothing changes for non-Intel (already "auto").
#
# Patch 2 — remove ARM GPU tools from -Dtools=
#   Changes: -Dtools=drm-shim,etnaviv,freedreno,glsl,intel,nir,nouveau,lima,panfrost,asahi,imagination,dlclose-skip
#        to: -Dtools=drm-shim,glsl,intel,nir,nouveau,dlclose-skip
#   Removed tools and what they are:
#     freedreno   — Qualcomm Adreno debug/disassembly tools (forces libfreedreno_layout.a)
#     etnaviv     — Vivante GPU tools (forces libetnaviv)
#     lima        — ARM Mali Utgard tools
#     panfrost    — ARM Mali Midgard/Bifrost tools
#     asahi       — Apple Silicon GPU tools (macOS Metal backend)
#     imagination — PowerVR GPU tools
#   These are all irrelevant on x86 hardware and produce zero useful output there.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# - The installed mesa lacks Adreno/Mali/Apple debug tools (e.g. freedreno-dump,
#   lima_disasm). These are only useful when you physically have one of those GPUs.
# - All OpenGL/Vulkan drivers for the actual hardware (NVIDIA, AMD, Intel) are
#   unaffected and fully functional.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# Patch 1: When the upstream formula stops using "all" on Intel x86, or when
#   GCC 12 is no longer the system compiler (gcc 13+ handles the vector type
#   conversions differently). Check mesa.rb for the drivers= line.
#
# Patch 2: When the upstream formula conditionalises -Dtools= on the target
#   architecture (i.e. only includes ARM tools when building for ARM). This is
#   a known packaging oversight that may be fixed upstream.
#   Check: grep 'freedreno' <path-to-mesa.rb>
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_MESA=0 to skip these patches (e.g. after upstream fixes them
# or to diagnose whether they're still needed):
#   DF_PATCH_BREW_MESA=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping mesa patch"; exit 0; }

# Allow opting out via DF_PATCH_BREW_MESA=0
if [[ "${DF_PATCH_BREW_MESA:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_MESA=0 — skipping mesa formula patches"
    exit 0
fi

MESA_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/m/mesa.rb"

[[ -f "$MESA_RB" ]] || { log_warn "mesa.rb not found at $MESA_RB — skipping"; exit 0; }

log_section "Patching mesa formula for Linux (x86 drivers only)"

# Helper: idempotent literal-string replacement via python3.
# Uses python rather than sd/sed because the target strings contain '?' which is
# a regex metacharacter — literal replacement avoids silent partial matches.
# Prints: 'already' | 'patched' | 'notfound'
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

# Patch 1: drivers = "all" → "auto" on Intel (see header for details)
_result=$(_replace "$MESA_RB" \
    'drivers = Hardware::CPU.intel? ? "all" : "auto"' \
    'drivers = Hardware::CPU.intel? ? "auto" : "auto"')
case "$_result" in
    already)  log_okay "Patch 1 (drivers=auto) already applied" ;;
    patched)  log_okay "Patch 1: drivers=all → drivers=auto on Intel x86" ;;
    notfound) log_warn "Patch 1 target not found — formula may have changed; check mesa.rb" ;;
esac

# Patch 2: remove ARM GPU tools from -Dtools= (see header for details)
# Keep:    drm-shim, glsl, intel, nir, nouveau, dlclose-skip  (all x86-relevant)
# Remove:  freedreno, etnaviv, lima, panfrost, asahi, imagination  (ARM/mobile only)
_result=$(_replace "$MESA_RB" \
    '-Dtools=drm-shim,etnaviv,freedreno,glsl,intel,nir,nouveau,lima,panfrost,asahi,imagination,dlclose-skip' \
    '-Dtools=drm-shim,glsl,intel,nir,nouveau,dlclose-skip')
case "$_result" in
    already)  log_okay "Patch 2 (tools=x86-only) already applied" ;;
    patched)  log_okay "Patch 2: removed ARM GPU tools from -Dtools=" ;;
    notfound) log_warn "Patch 2 target not found — formula may have changed; check mesa.rb" ;;
esac

unset -f _replace

log_okay "mesa.rb patches done"
