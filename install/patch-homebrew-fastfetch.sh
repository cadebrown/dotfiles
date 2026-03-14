#!/usr/bin/env bash
# install/patch-homebrew-fastfetch.sh - patch the fastfetch formula for Linux
#
# Problem: fastfetch auto-detects directx-headers (installed as mesa dep) and
# compiles gpu_wsl.cpp — the WSL GPU detection module. This file includes
# <wsl/winadapter.h> which needs <unknwn.h> from directx-headers stubs.
# On a custom Homebrew prefix the stubs include path is not picked up correctly
# by the Homebrew gcc shim, causing a "fatal error: unknwn.h: No such file or
# directory" build failure.
#
# Fix: pass -DENABLE_DIRECTX_HEADERS=OFF on Linux. The WSL GPU path is only
# relevant in a WSL environment; on a standard Linux system it's a no-op anyway.
#
# Safe to re-run: idempotent (checks before applying).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping fastfetch patch"; exit 0; }

FASTFETCH_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/f/fastfetch.rb"

[[ -f "$FASTFETCH_RB" ]] || { log_warn "fastfetch.rb not found at $FASTFETCH_RB — skipping"; exit 0; }

log_section "Patching fastfetch formula for Linux (disable DirectX headers)"

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
    # WSL GPU detection (gpu_wsl.cpp) fails to build with GCC 12 on Linux due to
    # unknwn.h not being found from winadapter.h when using a custom Homebrew prefix.
    # Not needed on a standard Linux system (non-WSL).
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
    patched)  log_okay "Patched: disabled ENABLE_DIRECTX_HEADERS for Linux build" ;;
    notfound) log_warn "fastfetch patch target not found — formula may have changed" ;;
esac
unset _PATCH _FIX _result

log_okay "fastfetch.rb patched successfully"
