#!/usr/bin/env bash
# install/patch-homebrew-rpm.sh — patch rpm.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# rpm depends on lua for its Lua scripting support. CMake's FindLua module finds
# LUA_LIBRARY correctly (liblua5.5.so in the Homebrew prefix), but also needs
# LUA_MATH_LIBRARY (libm) to compute LUA_LIBRARIES = "liblua;libm".
#
# In Homebrew's superenv on a custom prefix, cmake's find_library() is restricted
# to search only within the Homebrew prefix and its dependencies. libm (glibc's
# math library) is in a keg-only glibc formula at opt/glibc/lib/libm.so — it is
# NOT linked into the main Homebrew prefix because glibc is keg-only. cmake's
# find_library() therefore cannot find libm and sets:
#
#   LUA_MATH_LIBRARY:FILEPATH=LUA_MATH_LIBRARY-NOTFOUND
#
# FindLua then computes LUA_LIBRARIES = "liblua5.5.so;LUA_MATH_LIBRARY-NOTFOUND",
# and find_package_handle_standard_args rejects it because LUA_LIBRARIES contains
# a "NOTFOUND" component, producing:
#
#   Could NOT find Lua (missing: LUA_LIBRARIES)
#
# The fix: pass -DLUA_MATH_LIBRARY= pointing to glibc's libm.so explicitly.
# This bypasses the failed find_library() call and gives FindLua the correct path.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Adds a Linux-only cmake argument before the system "cmake" call:
#
# Before:
#   args += %w[-DWITH_LIBELF=OFF -DWITH_LIBDW=OFF] if OS.mac?
#
# After:
#   args += %w[-DWITH_LIBELF=OFF -DWITH_LIBDW=OFF] if OS.mac?
#   if OS.linux?
#     # cmake's find_library() cannot find glibc's libm in the superenv because
#     # glibc is keg-only and its lib dir is not in cmake's search path.
#     # FindLua requires LUA_MATH_LIBRARY (libm) to construct LUA_LIBRARIES.
#     args << "-DLUA_MATH_LIBRARY=#{Formula["glibc"].opt_lib/"libm.so"}"
#   end
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# None. LUA_MATH_LIBRARY is the same libm.so that cmake would have found if it
# could search glibc's lib directory. macOS builds are unaffected.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When Homebrew's superenv or cmake integration adds glibc to cmake's find_library
# search path on Linux, or when the rpm formula handles this explicitly.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_RPM=0 to skip:
#   DF_PATCH_BREW_RPM=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping rpm patch"; exit 0; }

if [[ "${DF_PATCH_BREW_RPM:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_RPM=0 — skipping rpm formula patch"
    exit 0
fi

RPM_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/rpm.rb"

[[ -f "$RPM_RB" ]] || { log_warn "rpm.rb not found at $RPM_RB — skipping"; exit 0; }

log_section "Patching rpm formula for Linux (LUA_MATH_LIBRARY from glibc)"

_ORIG='    args += %w[-DWITH_LIBELF=OFF -DWITH_LIBDW=OFF] if OS.mac?'

_FIX='    args += %w[-DWITH_LIBELF=OFF -DWITH_LIBDW=OFF] if OS.mac?
    if OS.linux?
      # cmake'\''s find_library() cannot find glibc'\''s libm in the superenv because
      # glibc is keg-only and its lib dir is not in cmake'\''s find_library search path.
      # FindLua requires LUA_MATH_LIBRARY (libm) to construct LUA_LIBRARIES. Without
      # this, FindLua sets LUA_MATH_LIBRARY=NOTFOUND and the Lua check fails.
      args << "-DLUA_MATH_LIBRARY=#{Formula["glibc"].opt_lib/"libm.so"}"
    end'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$RPM_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "rpm LUA_MATH_LIBRARY patch already applied" ;;
    patched)  log_okay "Patched: rpm passes LUA_MATH_LIBRARY=glibc/lib/libm.so to cmake" ;;
    notfound) log_warn "rpm patch target not found — formula may have changed; check rpm.rb" ;;
esac
unset _ORIG _FIX _result

log_okay "rpm.rb patch done"
