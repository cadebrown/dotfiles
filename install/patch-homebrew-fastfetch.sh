#!/usr/bin/env bash
# install/patch-homebrew-fastfetch.sh — patch fastfetch.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# fastfetch's cmake build auto-detects optional libraries. On Linux, mesa is a
# build dependency of fastfetch (for GPU info detection via libdrm/EGL). Mesa in
# turn depends on directx-headers — a Microsoft package providing D3D12/DX12
# headers for use on Linux (primarily for WSL and DXVK).
#
# Because directx-headers is present in the Homebrew Cellar, fastfetch's cmake
# finds it via pkg-config and enables the WSL GPU detection module by setting
# FF_HAVE_DIRECTX_HEADERS=1. This causes gpu_wsl.cpp to be compiled.
#
# gpu_wsl.cpp:11 includes <wsl/winadapter.h>, which immediately does:
#   #include <unknwn.h>   — a Windows COM interface definition
#
# The stubs providing unknwn.h for Linux live in:
#   directx-headers/include/wsl/stubs/unknwn.h
# These are registered in the DirectX-Headers.pc pkg-config file, so in theory
# they should be in the include path. In practice, under a custom Homebrew prefix
# the Homebrew GCC shim adds the generic $BREW_PREFIX/include to the system
# include path. This causes winadapter.h to be found at $BREW_PREFIX/include/wsl/
# (the system-linked copy) rather than the Cellar copy, and the stubs directory
# is not in the search path at that point — producing:
#   fatal error: unknwn.h: No such file or directory
#
# We spent time verifying this: compiling a test file with the exact same flags
# manually (g++ -std=c++17 -I<stubs> ...) works fine. The failure is specific to
# the shim/cmake interaction at a custom prefix. The simplest correct fix is to
# just not compile the WSL module at all on non-WSL Linux.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Appends to the cmake args in the install def:
#   args << "-DENABLE_DIRECTX_HEADERS=OFF" if OS.linux?
#
# ENABLE_DIRECTX_HEADERS is a first-class cmake option in fastfetch (see its
# CMakeLists.txt: cmake_dependent_option(ENABLE_DIRECTX_HEADERS ...)). Setting
# it OFF disables compilation of gpu_wsl.cpp and clears FF_HAVE_DIRECTX_HEADERS.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# - fastfetch will not report GPU info from the WSL D3D12 driver path.
# - On a standard Linux system (not WSL), this path reports nothing useful anyway
#   — it exists solely to read GPU data from the Windows host via the WSL2 kernel
#   bridge. On bare-metal Linux or a VM the WSL GPU detection always returns empty.
# - All other GPU detection paths (via libdrm, /sys/class/drm, Vulkan, OpenCL)
#   remain fully functional and are what actually populates GPU info on bare metal.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When either:
# a) The fastfetch formula explicitly handles the stubs include path on Linux
#    (e.g. passes -I$(pkg-config --variable=wslstubsdir DirectX-Headers)), OR
# b) The fastfetch formula already sets ENABLE_DIRECTX_HEADERS=OFF on Linux
#    (check: grep DIRECTX fastfetch.rb)
# c) Homebrew fixes its shim to not interfere with pkg-config include paths at
#    custom prefixes — unlikely as this would be a broader shim change.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_FASTFETCH=0 to skip:
#   DF_PATCH_BREW_FASTFETCH=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping fastfetch patch"; exit 0; }

# Allow opting out via DF_PATCH_BREW_FASTFETCH=0
if [[ "${DF_PATCH_BREW_FASTFETCH:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_FASTFETCH=0 — skipping fastfetch formula patch"
    exit 0
fi

FASTFETCH_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/f/fastfetch.rb"

[[ -f "$FASTFETCH_RB" ]] || { log_warn "fastfetch.rb not found at $FASTFETCH_RB — skipping"; exit 0; }

log_section "Patching fastfetch formula for Linux (disable WSL GPU detection)"

# The patch appends -DENABLE_DIRECTX_HEADERS=OFF after the args = %W[...] block.
# We anchor on the closing ] of the args array to ensure we insert in the right place.
_PATCH='    args = %W[
      -DCMAKE_INSTALL_SYSCONFDIR=#{etc}
      -DBUILD_FLASHFETCH=OFF
      -DENABLE_SYSTEM_YYJSON=ON
    ]'
_FIX='    args = %W[
      -DCMAKE_INSTALL_SYSCONFDIR=#{etc}
      -DBUILD_FLASHFETCH=OFF
      -DENABLE_SYSTEM_YYJSON=ON
    ]
    # WSL GPU detection (gpu_wsl.cpp) fails at a custom Homebrew prefix: the GCC
    # shim adds $BREW_PREFIX/include to the system path, causing winadapter.h to
    # be found before its stubs dir is on the include path, so <unknwn.h> is not
    # found. On non-WSL Linux this module reports nothing useful anyway.
    args << "-DENABLE_DIRECTX_HEADERS=OFF" if OS.linux?'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$FASTFETCH_RB" "$_PATCH" "$_FIX")
case "$_result" in
    already)  log_okay "fastfetch DirectX-Headers patch already applied" ;;
    patched)  log_okay "Patched: -DENABLE_DIRECTX_HEADERS=OFF added for Linux" ;;
    notfound) log_warn "fastfetch patch target not found — formula may have changed; check fastfetch.rb" ;;
esac
unset _PATCH _FIX _result

log_okay "fastfetch.rb patches done"
