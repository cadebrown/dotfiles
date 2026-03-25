#!/usr/bin/env bash
# install/patch-homebrew-stdenv.sh — patch Homebrew's Linux stdenv to fix
# two endemic build failures on a custom prefix
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# On Linux with a custom Homebrew prefix (not /home/linuxbrew/.linuxbrew), all
# packages must be built from source because bottles are path-locked. Two
# systematic failures affect nearly every package built from source:
#
# (1) MISSING KERNEL HEADERS
#     Homebrew glibc headers chain to Linux kernel headers:
#       glibc/include/bits/errno.h     → <linux/errno.h>
#       glibc/include/bits/local_lim.h → <linux/limits.h>
#       glibc/include/bits/ioctls.h    → <asm/ioctls.h>
#       glibc/include/bits/sockaddr.h  → <linux/socket.h>
#       glibc/include/bits/fcntl-linux.h → <linux/falloc.h>
#     Homebrew provides linux-headers@6.8 for this purpose, but it is keg-only
#     and not in HOMEBREW_PREFIX/include. Without it in CPATH, source builds
#     fail with "fatal error: linux/errno.h: No such file or directory".
#
# (2) BROKEN GNULIB PROBE
#     Many packages bundle gnulib, which includes AC_C_UNDECLARED_BUILTIN_OPTIONS.
#     This macro tries to find compiler flags to error on undeclared builtins, by
#     compiling a test program calling memcpy/strchr without a header. In
#     Homebrew's build environment, GCC treats these as compiler builtins
#     (__builtin_memcpy etc.) so the test compiles silently regardless of flags.
#     The probe records "cannot detect" and configure aborts:
#       configure: error: cannot make gcc-NN report undeclared builtins
#     Affected packages include: m4, pkgconf, libx11, and any package bundling
#     a gnulib version with the broken probe.
#
# Both failures require patching each affected formula's Ruby install def
# individually. This is unsustainable as new packages are added or discovered.
# The proper fix is to configure Homebrew's build environment setup once.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# In setup_build_environment in std.rb, after the existing LD_RUN_PATH setup:
#
# (1) Adds linux-headers@6.8 include directory to CPATH globally:
#       linux_headers = begin
#         ::Formula["linux-headers@6.8"]
#       rescue ::FormulaUnavailableError
#         nil
#       end
#       prepend_path "CPATH", linux_headers.include if linux_headers
#     The rescue guard makes this a no-op before linux-headers@6.8 is installed.
#
# (2) Pre-sets the autoconf cache variable to skip the broken gnulib probe:
#       self["ac_cv_c_undeclared_builtin_options"] = \
#         "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
#     Autoconf reads ac_cv_* env vars as pre-cached answers, skipping the probe.
#
# ─── INTERACTION WITH PER-FORMULA PATCHES ───────────────────────────────────────
#
# Per-formula patches (ncurses, m4, pkgconf, cc65) also set CPATH and/or
# ac_cv_c_undeclared_builtin_options. With this stdenv patch in place, those
# are redundant but harmless. They can be removed incrementally.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# All source builds on Linux see linux-headers@6.8 in CPATH and have the gnulib
# probe pre-answered. Both are correct: glibc always needs kernel headers, and
# the gnulib probe is a known bug that produces wrong results in this environment.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When upstream Homebrew adds linux-headers@6.8 as an implicit build dependency
# for all Linux source builds, AND when gnulib fixes the broken probe in all
# widely-used packages. Until both are true, this patch is needed.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_STDENV=0 to skip:
#   DF_PATCH_BREW_STDENV=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping stdenv patch"; exit 0; }

if [[ "${DF_PATCH_BREW_STDENV:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_STDENV=0 — skipping Homebrew stdenv patch"
    exit 0
fi

STDENV_RB="$LOCAL_PLAT/brew/Homebrew/Library/Homebrew/extend/os/linux/extend/ENV/std.rb"

[[ -f "$STDENV_RB" ]] || { log_warn "std.rb not found at $STDENV_RB — skipping"; exit 0; }

log_section "Patching Homebrew stdenv for Linux (linux-headers CPATH + gnulib probe fix)"

_ORIG='        prepend_path "CPATH", HOMEBREW_PREFIX/"include"
        prepend_path "LIBRARY_PATH", HOMEBREW_PREFIX/"lib"
        prepend_path "LD_RUN_PATH", HOMEBREW_PREFIX/"lib"

        return unless formula'

# v1: linux-headers CPATH only, no gnulib probe fix
_LINUX_HEADERS_ONLY='        prepend_path "CPATH", HOMEBREW_PREFIX/"include"
        prepend_path "LIBRARY_PATH", HOMEBREW_PREFIX/"lib"
        prepend_path "LD_RUN_PATH", HOMEBREW_PREFIX/"lib"

        # linux-headers@6.8 provides kernel headers required by Homebrew glibc
        # transitively (bits/errno.h → linux/errno.h, bits/local_lim.h →
        # linux/limits.h, etc.). Any formula built from source on a custom prefix
        # needs these headers. linux-headers@6.8 is keg-only so it is not in
        # HOMEBREW_PREFIX/include — add it explicitly.
        # The rescue guard makes this a no-op if linux-headers@6.8 is not yet
        # installed (e.g. during bootstrap before it has been installed).
        linux_headers = begin
          ::Formula["linux-headers@6.8"]
        rescue ::FormulaUnavailableError
          nil
        end
        prepend_path "CPATH", linux_headers.include if linux_headers

        return unless formula'

# v2 (correct): linux-headers CPATH + gnulib probe bypass
_FULL_FIX='        prepend_path "CPATH", HOMEBREW_PREFIX/"include"
        prepend_path "LIBRARY_PATH", HOMEBREW_PREFIX/"lib"
        prepend_path "LD_RUN_PATH", HOMEBREW_PREFIX/"lib"

        # linux-headers@6.8 provides kernel headers required by Homebrew glibc
        # transitively (bits/errno.h → linux/errno.h, bits/local_lim.h →
        # linux/limits.h, etc.). Any formula built from source on a custom prefix
        # needs these headers. linux-headers@6.8 is keg-only so it is not in
        # HOMEBREW_PREFIX/include — add it explicitly.
        # The rescue guard makes this a no-op if linux-headers@6.8 is not yet
        # installed (e.g. during bootstrap before it has been installed).
        linux_headers = begin
          ::Formula["linux-headers@6.8"]
        rescue ::FormulaUnavailableError
          nil
        end
        prepend_path "CPATH", linux_headers.include if linux_headers

        # Pre-set the autoconf cache variable for the broken gnulib
        # AC_C_UNDECLARED_BUILTIN_OPTIONS probe. In Homebrew'"'"'s build
        # environment, GCC treats memcpy/strchr as compiler builtins so the
        # probe compiles silently regardless of flags, and configure aborts with
        # "cannot make gcc-NN report undeclared builtins". Many packages bundle
        # gnulib (m4, pkgconf, libx11, etc.) and hit this. Pre-setting the
        # autoconf cache variable skips the probe entirely for all of them.
        self["ac_cv_c_undeclared_builtin_options"] = \
          "-Wimplicit-function-declaration -Werror=implicit-function-declaration"

        return unless formula'

_result=$(python3 -c "
import sys
path = sys.argv[1]
orig, linux_headers_only, full_fix = sys.argv[2], sys.argv[3], sys.argv[4]
txt = open(path).read()
if full_fix in txt:
    print('already')
elif linux_headers_only in txt:
    open(path,'w').write(txt.replace(linux_headers_only, full_fix, 1))
    print('migrated')
elif orig in txt:
    open(path,'w').write(txt.replace(orig, full_fix, 1))
    print('patched')
else:
    print('notfound')
" "$STDENV_RB" "$_ORIG" "$_LINUX_HEADERS_ONLY" "$_FULL_FIX")
case "$_result" in
    already)  log_okay "Homebrew stdenv full patch (linux-headers + gnulib probe fix) already applied" ;;
    migrated) log_okay "Migrated: stdenv patch updated to also include gnulib probe bypass" ;;
    patched)  log_okay "Patched: linux-headers CPATH + gnulib probe bypass added to stdenv" ;;
    notfound) log_warn "stdenv patch target not found — std.rb may have changed; check manually" ;;
esac
unset _ORIG _LINUX_HEADERS_ONLY _FULL_FIX _result

log_okay "std.rb patch done"
