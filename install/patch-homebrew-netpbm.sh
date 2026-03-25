#!/usr/bin/env bash
# install/patch-homebrew-netpbm.sh — patch netpbm.rb for GCC 15 C23 bool issue
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# GCC 15 tightened error handling in two ways that break netpbm:
#
# (1) C23 IS NOW THE DEFAULT STANDARD
#     GCC 15 changed its default C standard from C17 to C23. In C23, `bool` is a
#     built-in keyword. Code that tries to typedef bool fails:
#
#       libopt.c:92:23: error: 'bool' cannot be defined via 'typedef'
#       typedef unsigned char bool;
#       note: 'bool' is a keyword with '-std=c23' onwards
#
#     netpbm's buildtools/libopt.c has exactly this typedef. The error occurs in
#     the buildtools/ phase, preventing the main build from starting.
#
# (2) -Wincompatible-pointer-types IS NOW AN ERROR
#     GCC 15 promotes -Wincompatible-pointer-types from warning to error. netpbm's
#     converter/other/jpeg2000/libjasper_compat.c has:
#
#       *errorP = errorP;  (assigns const char ** to const char * — likely a typo)
#
#     This was a warning in GCC 14 and earlier; GCC 15 makes it fatal.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# In the install def, after the existing clang implicit-function-declaration fix,
# adds a Linux guard with two flags:
#
# Before:
#   ENV.append_to_cflags "-Wno-implicit-function-declaration" if DevelopmentTools.clang_build_version >= 1403
#
# After:
#   ENV.append_to_cflags "-Wno-implicit-function-declaration" if DevelopmentTools.clang_build_version >= 1403
#   if OS.linux?
#     # GCC 15 defaults to C23 (bool typedef fails) and promotes
#     # -Wincompatible-pointer-types to error. Suppress both.
#     ENV.append_to_cflags "-std=gnu17 -Wno-incompatible-pointer-types"
#   end
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# netpbm builds with -std=gnu17 on Linux (same standard GCC 14 used by default)
# and with -Wno-incompatible-pointer-types to suppress the libjasper_compat.c bug.
# No functionality is lost — netpbm does not use C23 features and libjasper_compat
# is a thin wrapper whose bug is cosmetic (wrong assignment, not runtime crash).
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When upstream netpbm fixes both the bool typedef and the incompatible-pointer
# bug, OR when the formula adds explicit GCC 15 handling, OR when netpbm is no
# longer a dependency.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_NETPBM=0 to skip:
#   DF_PATCH_BREW_NETPBM=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping netpbm patch"; exit 0; }

if [[ "${DF_PATCH_BREW_NETPBM:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_NETPBM=0 — skipping netpbm formula patch"
    exit 0
fi

NETPBM_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/n/netpbm.rb"

[[ -f "$NETPBM_RB" ]] || { log_warn "netpbm.rb not found at $NETPBM_RB — skipping"; exit 0; }

log_section "Patching netpbm formula for Linux (GCC 15 C23 bool typedef fix)"

_ORIG='    ENV.append_to_cflags "-Wno-implicit-function-declaration" if DevelopmentTools.clang_build_version >= 1403'

_FIX='    ENV.append_to_cflags "-Wno-implicit-function-declaration" if DevelopmentTools.clang_build_version >= 1403
    if OS.linux?
      # GCC 15 defaults to C23 (bool typedef in buildtools/libopt.c fails) and
      # promotes -Wincompatible-pointer-types to error (libjasper_compat.c bug).
      ENV.append_to_cflags "-std=gnu17 -Wno-incompatible-pointer-types"
    end'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$NETPBM_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "netpbm C23 bool patch already applied" ;;
    patched)  log_okay "Patched: netpbm builds with -std=gnu17 -Wno-incompatible-pointer-types on Linux (GCC 15 fixes)" ;;
    notfound) log_warn "netpbm patch target not found — formula may have changed; check netpbm.rb" ;;
esac
unset _ORIG _FIX _result

log_okay "netpbm.rb patch done"
